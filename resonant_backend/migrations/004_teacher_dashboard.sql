-- Migration 004: indexes for teacher dashboard queries
-- Adds composite index on learners (teacher_id, created_at DESC)
-- All needed metrics (last_active_at, accuracy, etc.) are computed directly
-- from existing practice_attempts and skill_progress tables.

CREATE INDEX IF NOT EXISTS learners_teacher_created_idx
    ON resonant.learners (teacher_id, created_at DESC)
    WHERE teacher_id IS NOT NULL;

