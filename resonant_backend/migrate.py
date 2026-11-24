"""Apply versioned SQL migrations to the isolated `resonant` schema."""

from pathlib import Path
import re

from database import get_connection


MIGRATIONS_DIR = Path(__file__).parent / "migrations"


def split_sql_statements(sql: str) -> list[str]:
    """Split PostgreSQL migration text at semicolons outside SQL literals/comments.

    This handles line comments, nested block comments, quoted identifiers,
    ordinary/escape strings, and dollar-quoted strings without another parser
    dependency. The repository migrations use plain DDL, but the lexer avoids
    executing comment fragments if their text contains semicolons.
    """
    statements: list[str] = []
    statement: list[str] = []
    index = 0
    length = len(sql)
    state: str | None = None
    block_depth = 0
    dollar_delimiter: str | None = None
    escape_string = False

    while index < length:
        char = sql[index]
        next_char = sql[index + 1] if index + 1 < length else ""

        if state == "line_comment":
            if char == "\n":
                state = None
                statement.append("\n")
            index += 1
            continue

        if state == "block_comment":
            if char == "/" and next_char == "*":
                block_depth += 1
                index += 2
            elif char == "*" and next_char == "/":
                block_depth -= 1
                index += 2
                if block_depth == 0:
                    state = None
            else:
                index += 1
            continue

        if state == "single_quote":
            statement.append(char)
            if escape_string and char == "\\" and index + 1 < length:
                statement.append(sql[index + 1])
                index += 2
            elif char == "'":
                if next_char == "'":
                    statement.append(next_char)
                    index += 2
                else:
                    state = None
                    index += 1
            else:
                index += 1
            continue

        if state == "double_quote":
            statement.append(char)
            if char == '"':
                if next_char == '"':
                    statement.append(next_char)
                    index += 2
                else:
                    state = None
                    index += 1
            else:
                index += 1
            continue

        if state == "dollar_quote":
            if sql.startswith(dollar_delimiter or "", index):
                statement.append(dollar_delimiter or "")
                index += len(dollar_delimiter or "")
                state = None
                dollar_delimiter = None
            else:
                statement.append(char)
                index += 1
            continue

        if char == "-" and next_char == "-":
            state = "line_comment"
            index += 2
            continue
        if char == "/" and next_char == "*":
            state = "block_comment"
            block_depth = 1
            statement.append(" ")
            index += 2
            continue
        if char == "'":
            escape_string = (
                index > 0
                and sql[index - 1] in "eE"
                and (index < 2 or not (sql[index - 2].isalnum() or sql[index - 2] in "_$"))
            )
            state = "single_quote"
            statement.append(char)
            index += 1
            continue
        if char == '"':
            state = "double_quote"
            statement.append(char)
            index += 1
            continue
        if char == "$":
            delimiter_match = re.match(r"\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$", sql[index:])
            if delimiter_match:
                dollar_delimiter = delimiter_match.group(0)
                state = "dollar_quote"
                statement.append(dollar_delimiter)
                index += len(dollar_delimiter)
                continue
        if char == ";":
            text = "".join(statement).strip()
            if text:
                statements.append(text)
            statement.clear()
            index += 1
            continue

        statement.append(char)
        index += 1

    if state in {"single_quote", "double_quote", "block_comment", "dollar_quote"}:
        raise ValueError(f"Unterminated PostgreSQL {state.replace('_', ' ')}.")

    final_statement = "".join(statement).strip()
    if final_statement:
        statements.append(final_statement)
    return statements


def run_migrations(connection_factory=get_connection, migrations_dir=MIGRATIONS_DIR):
    applied_now = []
    with connection_factory() as connection:
        connection.execute(
            "SELECT pg_advisory_xact_lock(hashtext('resonant_schema_migrations'))"
        )
        connection.execute("CREATE SCHEMA IF NOT EXISTS resonant")
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS resonant.schema_migrations (
                version INTEGER PRIMARY KEY,
                filename TEXT NOT NULL,
                applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """
        )
        rows = connection.execute(
            "SELECT version FROM resonant.schema_migrations"
        ).fetchall()
        applied = {row["version"] for row in rows}

        for path in sorted(Path(migrations_dir).glob("[0-9]*_*.sql")):
            match = re.match(r"^(\d+)_", path.name)
            if not match:
                continue
            version = int(match.group(1))
            if version in applied:
                continue

            try:
                sql = path.read_text(encoding="utf-8")
                for statement in split_sql_statements(sql):
                    connection.execute(statement)
                connection.execute(
                    """
                    INSERT INTO resonant.schema_migrations (version, filename)
                    VALUES (%s, %s)
                    """,
                    (version, path.name),
                )
                applied_now.append(version)
            except Exception as error:
                raise RuntimeError(
                    f"Migration {version} ({path.name}) failed: {error}"
                ) from error
    return applied_now


if __name__ == "__main__":
    print(f"Applied migrations: {run_migrations()}")
