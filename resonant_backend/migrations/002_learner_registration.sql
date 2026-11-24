-- Migration 002: extend learners table for teacher-assisted registration.
-- Adds name, phone, email, batch, consent_at, code_hash, registered_by.
-- Phone and email must be unique when present (nullable unique indexes).
-- Does NOT edit tables or indexes created by 001.

ALTER TABLE resonant.learners
    ADD COLUMN IF NOT EXISTS name        TEXT,
    ADD COLUMN IF NOT EXISTS phone       TEXT,
    ADD COLUMN IF NOT EXISTS email       TEXT,
    ADD COLUMN IF NOT EXISTS batch       TEXT,
    ADD COLUMN IF NOT EXISTS consent_at  TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS code_hash   TEXT,
    ADD COLUMN IF NOT EXISTS registered_by TEXT;

-- Unique partial indexes allow multiple NULL values while enforcing uniqueness
-- for non-NULL phone/email (standard PostgreSQL behaviour for nullable uniques).
CREATE UNIQUE INDEX IF NOT EXISTS learners_phone_unique_idx
    ON resonant.learners (phone)
    WHERE phone IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS learners_email_unique_idx
    ON resonant.learners (email)
    WHERE email IS NOT NULL;

