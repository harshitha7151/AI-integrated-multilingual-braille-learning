-- Migration 005: normalized lesson-assessment records and adaptive decisions.
-- This is additive. Existing practice attempts, quiz results, and progress rows
-- remain unchanged.

CREATE TABLE IF NOT EXISTS resonant.assessment_sessions (
    assessment_id UUID PRIMARY KEY,
    submission_id UUID NOT NULL UNIQUE,
    learner_id UUID NOT NULL REFERENCES resonant.learners(learner_id) ON DELETE CASCADE,
    assessment_key TEXT NOT NULL CHECK (length(assessment_key) BETWEEN 1 AND 160),
    lesson_id TEXT NOT NULL CHECK (length(lesson_id) BETWEEN 1 AND 160),
    language TEXT NOT NULL CHECK (language IN ('English', 'Hindi', 'Kannada')),
    assessment_type TEXT NOT NULL CHECK (assessment_type IN
        ('lesson', 'skill', 'word', 'module', 'revision', 'retention')),
    difficulty SMALLINT NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
    generated_content_version TEXT NOT NULL CHECK
        (length(generated_content_version) BETWEEN 1 AND 80),
    question_count INTEGER NOT NULL CHECK (question_count > 0),
    score INTEGER NOT NULL CHECK (score >= 0 AND score <= question_count),
    duration_ms INTEGER NOT NULL CHECK (duration_ms >= 0),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS assessment_sessions_learner_time_idx
    ON resonant.assessment_sessions (learner_id, completed_at DESC);
CREATE INDEX IF NOT EXISTS assessment_sessions_learner_lesson_idx
    ON resonant.assessment_sessions (learner_id, lesson_id, completed_at DESC);

CREATE TABLE IF NOT EXISTS resonant.assessment_questions (
    assessment_id UUID NOT NULL REFERENCES resonant.assessment_sessions(assessment_id)
        ON DELETE CASCADE,
    question_id TEXT NOT NULL CHECK (length(question_id) BETWEEN 1 AND 160),
    question_order INTEGER NOT NULL CHECK (question_order > 0),
    skill_id TEXT NOT NULL CHECK (length(skill_id) BETWEEN 1 AND 160),
    exercise_type TEXT NOT NULL CHECK (length(exercise_type) BETWEEN 1 AND 60),
    learning_objective TEXT NOT NULL CHECK (length(learning_objective) BETWEEN 1 AND 600),
    difficulty SMALLINT NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
    question_text TEXT NOT NULL CHECK (length(question_text) BETWEEN 1 AND 1200),
    options JSONB NOT NULL,
    expected_response JSONB NOT NULL,
    PRIMARY KEY (assessment_id, question_id)
);

CREATE TABLE IF NOT EXISTS resonant.assessment_attempts (
    attempt_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assessment_id UUID NOT NULL,
    question_id TEXT NOT NULL,
    learner_id UUID NOT NULL REFERENCES resonant.learners(learner_id) ON DELETE CASCADE,
    submitted_response JSONB NOT NULL,
    correct BOOLEAN NOT NULL,
    attempt_number INTEGER NOT NULL CHECK (attempt_number > 0),
    response_time_ms INTEGER NOT NULL CHECK (response_time_ms >= 0),
    hint_used BOOLEAN NOT NULL DEFAULT FALSE,
    error_category TEXT CHECK (error_category IS NULL OR error_category IN
        ('missing_dot', 'extra_dot', 'substitution', 'cell_order',
         'character_confusion', 'prerequisite_gap', 'unknown')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (assessment_id, question_id),
    FOREIGN KEY (assessment_id, question_id)
        REFERENCES resonant.assessment_questions(assessment_id, question_id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS assessment_attempts_learner_time_idx
    ON resonant.assessment_attempts (learner_id, created_at DESC);

CREATE TABLE IF NOT EXISTS resonant.assessment_error_summaries (
    learner_id UUID NOT NULL REFERENCES resonant.learners(learner_id) ON DELETE CASCADE,
    language TEXT NOT NULL CHECK (language IN ('English', 'Hindi', 'Kannada')),
    skill_id TEXT NOT NULL CHECK (length(skill_id) BETWEEN 1 AND 160),
    error_category TEXT NOT NULL CHECK (error_category IN
        ('missing_dot', 'extra_dot', 'substitution', 'cell_order',
         'character_confusion', 'prerequisite_gap', 'unknown')),
    error_count INTEGER NOT NULL DEFAULT 1 CHECK (error_count > 0),
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (learner_id, skill_id, error_category)
);

CREATE TABLE IF NOT EXISTS resonant.adaptive_decisions (
    decision_id UUID PRIMARY KEY,
    assessment_id UUID NOT NULL UNIQUE REFERENCES resonant.assessment_sessions(assessment_id)
        ON DELETE CASCADE,
    learner_id UUID NOT NULL REFERENCES resonant.learners(learner_id) ON DELETE CASCADE,
    action TEXT NOT NULL CHECK (action IN
        ('advance', 'reinforce', 'remedial_practice', 'revisit_prerequisite',
         'schedule_revision', 'increase_difficulty')),
    recommended_skill_id TEXT,
    recommended_lesson_id TEXT,
    reason TEXT NOT NULL CHECK (length(reason) BETWEEN 1 AND 1200),
    evidence JSONB NOT NULL,
    confidence NUMERIC(4, 3) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    expected_learning_objective TEXT NOT NULL CHECK
        (length(expected_learning_objective) BETWEEN 1 AND 600),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS adaptive_decisions_learner_time_idx
    ON resonant.adaptive_decisions (learner_id, created_at DESC);
