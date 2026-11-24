import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import migrate


class _Cursor:
    def __init__(self, rows=None):
        self._rows = rows or []

    def fetchall(self):
        return self._rows


class _MigrationConnection:
    def __init__(self, applied=(), fail_on=None):
        self.applied = list(applied)
        self.fail_on = fail_on
        self.statements = []
        self.exit_exception = None

    def __enter__(self):
        return self

    def __exit__(self, exception_type, exception, traceback):
        self.exit_exception = exception_type
        return False

    def execute(self, sql, params=None):
        self.statements.append((sql, params))
        if "SELECT version FROM resonant.schema_migrations" in sql:
            return _Cursor([{"version": version} for version in self.applied])
        if self.fail_on is not None and self.fail_on in sql:
            raise RuntimeError("simulated SQL execution error")
        return _Cursor()


class MigrationRunnerTests(unittest.TestCase):
    def test_splitter_ignores_semicolons_in_line_and_nested_block_comments(self):
        sql = """-- explanatory note; words after this are still comments
        CREATE TABLE resonant.one (id INTEGER); -- trailing comment; ignored
        /* outer comment;
           /* nested comment; */ still a comment;
        */
        CREATE TABLE resonant.two (note TEXT DEFAULT 'inside; string');
        SELECT/* retained token boundary; semicolon ignored */1;
        """

        statements = migrate.split_sql_statements(sql)

        self.assertEqual(len(statements), 3)
        self.assertTrue(statements[0].startswith("CREATE TABLE resonant.one"))
        self.assertTrue(statements[1].startswith("CREATE TABLE resonant.two"))
        self.assertIn("'inside; string'", statements[1])
        self.assertEqual(statements[2], "SELECT 1")
        self.assertNotIn("words after this", " ".join(statements))

    def test_splitter_handles_quoted_identifiers_dollar_strings_and_normal_sql(self):
        sql = '''CREATE TABLE resonant."semi;colon" (id INTEGER);
        DO $migration$
        BEGIN
            PERFORM 'inside; body';
        END
        $migration$;
        INSERT INTO resonant.values_table(value) VALUES (E'escaped\\';still quoted');
        '''

        statements = migrate.split_sql_statements(sql)

        self.assertEqual(len(statements), 3)
        self.assertIn('"semi;colon"', statements[0])
        self.assertIn("$migration$", statements[1])
        self.assertIn("inside; body", statements[1])
        self.assertIn("still quoted", statements[2])

    def test_runner_skips_applied_migrations_and_records_new_version(self):
        connection = _MigrationConnection(applied=(1,))
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "001_existing.sql").write_text(
                "CREATE TABLE resonant.existing (id INTEGER);",
                encoding="utf-8",
            )
            Path(directory, "002_new.sql").write_text(
                "-- note; must not execute as SQL\n"
                "CREATE TABLE resonant.new_table (id INTEGER);",
                encoding="utf-8",
            )

            applied = migrate.run_migrations(
                connection_factory=lambda: connection,
                migrations_dir=Path(directory),
            )

        statements = [sql for sql, _ in connection.statements]
        self.assertEqual(applied, [2])
        self.assertFalse(any("resonant.existing" in sql for sql in statements))
        self.assertTrue(any("CREATE TABLE resonant.new_table" in sql for sql in statements))
        tracking = [
            params
            for sql, params in connection.statements
            if "INSERT INTO resonant.schema_migrations" in sql
        ]
        self.assertEqual(tracking, [(2, "002_new.sql")])
        self.assertIsNone(connection.exit_exception)

    def test_failed_migration_names_version_and_is_not_tracked(self):
        connection = _MigrationConnection(fail_on="CREATE TABLE resonant.broken")
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "009_broken.sql").write_text(
                "CREATE TABLE resonant.broken (id INTEGER);",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(
                RuntimeError, r"Migration 9 \(009_broken\.sql\) failed"
            ):
                migrate.run_migrations(
                    connection_factory=lambda: connection,
                    migrations_dir=Path(directory),
                )

        self.assertFalse(
            any("INSERT INTO resonant.schema_migrations" in sql for sql, _ in connection.statements)
        )
        self.assertIsNotNone(connection.exit_exception)

    def test_teacher_migration_is_additive_and_comment_is_not_executed(self):
        migration_path = migrate.MIGRATIONS_DIR / "003_teacher_accounts.sql"
        statements = migrate.split_sql_statements(
            migration_path.read_text(encoding="utf-8")
        )

        self.assertEqual(len(statements), 4)
        self.assertIn("CREATE TABLE IF NOT EXISTS resonant.teachers", statements[0])
        self.assertIn("CREATE UNIQUE INDEX IF NOT EXISTS", statements[1])
        self.assertIn("ADD COLUMN IF NOT EXISTS teacher_id UUID", statements[2])
        self.assertIn("REFERENCES resonant.teachers(teacher_id)", statements[2])
        self.assertIn("CREATE INDEX IF NOT EXISTS", statements[3])
        self.assertFalse(any(statement.lstrip().startswith("convert to FK") for statement in statements))
        self.assertFalse(any("DROP TABLE" in statement.upper() for statement in statements))
        self.assertFalse(any("DROP COLUMN" in statement.upper() for statement in statements))


if __name__ == "__main__":
    unittest.main()
