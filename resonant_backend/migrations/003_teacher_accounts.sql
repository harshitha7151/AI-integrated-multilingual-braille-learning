-- Migration 003: teacher accounts and link learners to teachers.
-- Does NOT edit tables from 001 or 002.

CREATE TABLE IF NOT EXISTS resonant.teachers (
    teacher_id  UUID PRIMARY KEY,
    name        TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
    email       TEXT NOT NULL CHECK (length(trim(email)) BETWEEN 3 AND 254),
    password_hash TEXT NOT NULL,
    organization TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS teachers_email_unique_idx
    ON resonant.teachers (lower(email));

-- Link learners to their registering teacher (nullable for legacy rows).
-- registered_by already exists as TEXT from 002; convert to FK if UUID, else
-- add a separate column to avoid breaking existing data.
ALTER TABLE resonant.learners
    ADD COLUMN IF NOT EXISTS teacher_id UUID
        REFERENCES resonant.teachers(teacher_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS learners_teacher_idx
    ON resonant.learners (teacher_id)
    WHERE teacher_id IS NOT NULL;

