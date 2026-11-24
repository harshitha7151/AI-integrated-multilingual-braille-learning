-- PROPOSAL ONLY. Do not run against any environment without privacy review,
-- explicit research-consent design, schema-owner approval, and a migration plan.
-- Adds minimal context to existing resonant.practice_attempts; stores no audio,
-- transcript, identity/contact fields, touch trajectory, or free-text answer.

ALTER TABLE resonant.practice_attempts
    ADD COLUMN IF NOT EXISTS session_id UUID,
    ADD COLUMN IF NOT EXISTS event_schema_version SMALLINT,
    ADD COLUMN IF NOT EXISTS client_version TEXT,
    ADD COLUMN IF NOT EXISTS item_version TEXT,
    ADD COLUMN IF NOT EXISTS difficulty_level SMALLINT,
    ADD COLUMN IF NOT EXISTS expected_response JSONB,
    ADD COLUMN IF NOT EXISTS submitted_response JSONB,
    ADD COLUMN IF NOT EXISTS error_category TEXT;

-- Proposed validation constraints are intentionally commented pending review.
-- ALTER TABLE resonant.practice_attempts ADD CONSTRAINT practice_event_schema_version_positive
--     CHECK (event_schema_version IS NULL OR event_schema_version > 0);
-- ALTER TABLE resonant.practice_attempts ADD CONSTRAINT practice_difficulty_level_range
--     CHECK (difficulty_level IS NULL OR difficulty_level BETWEEN 1 AND 5);
-- ALTER TABLE resonant.practice_attempts ADD CONSTRAINT practice_error_category_allowed
--     CHECK (error_category IS NULL OR error_category IN
--       ('missing_dot', 'extra_dot', 'substitution', 'cell_order', 'other', 'unknown'));

-- `expected_response` / `submitted_response` should be canonical structured
-- exercise responses (e.g. ordered six-bit cell masks), not speech text. For
-- non-Braille exercises, use a typed, minimal representation. Access and
-- retention must be restricted; research opt-in belongs in a separate
-- consent-governance flow and must not be inferred from this table.
-- `skill_id` already identifies the skill; prerequisite links belong in a
-- versioned curriculum catalog rather than duplicated per event.
