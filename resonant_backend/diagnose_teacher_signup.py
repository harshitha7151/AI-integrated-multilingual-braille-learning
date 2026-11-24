"""Read-only checks for the teacher signup runtime and PostgreSQL schema.

Run with the same Python environment and environment variables as Uvicorn:
    python diagnose_teacher_signup.py

This script never prints connection strings, passwords, emails, or JWT secrets,
and it never applies migrations or changes database contents.
"""

import importlib.metadata
import os
import sys

import teacher_service
from database import get_connection


def _version(package: str) -> str:
    try:
        return importlib.metadata.version(package)
    except importlib.metadata.PackageNotFoundError:
        return "missing"


def main() -> int:
    print(f"python_executable={sys.executable}")
    print(f"passlib_version={_version('passlib')}")
    print(f"bcrypt_version={_version('bcrypt')}")
    print(f"python_jose_version={_version('python-jose')}")
    print(f"psycopg_version={_version('psycopg')}")
    print(f"database_url_configured={bool(os.getenv('RESONANT_DATABASE_URL'))}")
    print(f"jwt_secret_configured={bool(os.getenv('RESONANT_JWT_SECRET'))}")

    try:
        password = "Resonant-diagnostic-only-password"
        password_hash = teacher_service._hash_password(password)
        print(
            "bcrypt_hash_verify="
            f"{teacher_service._verify_password(password, password_hash)}"
        )
    except Exception as error:
        print(f"bcrypt_hash_verify=failed ({type(error).__name__})")

    if not os.getenv("RESONANT_DATABASE_URL"):
        print("postgresql_check=skipped (RESONANT_DATABASE_URL is not configured)")
        return 2

    try:
        with get_connection() as connection:
            row = connection.execute(
                """
                SELECT current_database() AS database_name,
                       current_schema() AS current_schema,
                       to_regclass('resonant.teachers') IS NOT NULL AS teacher_table_exists,
                       to_regclass('resonant.schema_migrations') IS NOT NULL AS migrations_table_exists
                """
            ).fetchone()
            print(f"database_reachable=True")
            print(f"database_name={row['database_name']}")
            print(f"current_schema={row['current_schema']}")
            print(f"resonant_teachers_exists={row['teacher_table_exists']}")
            print(f"schema_migrations_exists={row['migrations_table_exists']}")
            if row["teacher_table_exists"]:
                columns = connection.execute(
                    """
                    SELECT column_name
                    FROM information_schema.columns
                    WHERE table_schema = 'resonant' AND table_name = 'teachers'
                    """
                ).fetchall()
                actual_columns = {column["column_name"] for column in columns}
                required_columns = {
                    "teacher_id", "name", "email", "password_hash",
                    "organization", "created_at",
                }
                missing_columns = sorted(required_columns - actual_columns)
                print(f"teacher_schema_complete={not missing_columns}")
                print(f"teacher_columns_missing={','.join(missing_columns) or 'none'}")
                index = connection.execute(
                    """
                    SELECT EXISTS (
                        SELECT 1 FROM pg_indexes
                        WHERE schemaname = 'resonant'
                          AND indexname = 'teachers_email_unique_idx'
                    ) AS exists
                    """
                ).fetchone()
                print(f"teacher_unique_email_index_exists={index['exists']}")
            if row["migrations_table_exists"]:
                migration = connection.execute(
                    "SELECT EXISTS(SELECT 1 FROM resonant.schema_migrations WHERE version = 3) AS applied"
                ).fetchone()
                print(f"teacher_migration_003_applied={migration['applied']}")
    except Exception as error:
        print(
            "database_reachable=False "
            f"error_type={type(error).__name__} "
            f"sqlstate={getattr(error, 'sqlstate', None) or 'unavailable'}"
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
