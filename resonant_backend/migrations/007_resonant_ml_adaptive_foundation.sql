-- Migration 007: governed Resonant ML/adaptive data foundation.
--
-- This migration is additive. It preserves all existing attempts, assessments,
-- decisions and learner records. New columns default to backward-compatible
-- values. Run against a disposable database before production deployment.

CREATE TABLE IF NOT EXISTS resonant.braille_mapping_versions (
    mapping_version TEXT PRIMARY KEY CHECK (length(mapping_version) BETWEEN 1 AND 120),
    registry_version TEXT NOT NULL CHECK (length(registry_version) BETWEEN 1 AND 120),
    languages TEXT[] NOT NULL,
    source_provenance JSONB NOT NULL,
    validation_status TEXT NOT NULL CHECK (validation_status IN
        ('verified_subset', 'review_required', 'retired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO resonant.braille_mapping_versions (
    mapping_version, registry_version, languages, source_provenance,
    validation_status
) VALUES
    (
        'ueb-grade1-iceb-2024-subset-v1',
        'resonant-braille-mappings-v1',
        ARRAY['English'],
        '{"source":"ICEB Rules of Unified English Braille, third edition, 2024","coverage":"project verified subset"}'::jsonb,
        'verified_subset'
    ),
    (
        'niepvd-bharati-2025-subset-v1',
        'resonant-braille-mappings-v1',
        ARRAY['Hindi','Kannada'],
        '{"source":"NIEPVD Bharati Braille Unicode chart, 2025","coverage":"project verified subset"}'::jsonb,
        'verified_subset'
    )
ON CONFLICT (mapping_version) DO NOTHING;

ALTER TABLE resonant.assessment_sessions
    ADD COLUMN IF NOT EXISTS eligible_question_count INTEGER;

UPDATE resonant.assessment_sessions
SET eligible_question_count = question_count
WHERE eligible_question_count IS NULL;

ALTER TABLE resonant.assessment_sessions
    ALTER COLUMN eligible_question_count SET NOT NULL;

ALTER TABLE resonant.assessment_sessions
    DROP CONSTRAINT IF EXISTS assessment_sessions_eligible_question_count_check;

ALTER TABLE resonant.assessment_sessions
    ADD CONSTRAINT assessment_sessions_eligible_question_count_check CHECK (
        eligible_question_count >= 0 AND
        eligible_question_count <= question_count AND
        score <= eligible_question_count
    );

ALTER TABLE resonant.assessment_questions
    ADD COLUMN IF NOT EXISTS question_instance_id UUID,
    ADD COLUMN IF NOT EXISTS question_source TEXT NOT NULL DEFAULT 'validated_catalog',
    ADD COLUMN IF NOT EXISTS question_version TEXT NOT NULL DEFAULT 'flutter-catalog-v1',
    ADD COLUMN IF NOT EXISTS generation_model TEXT;

ALTER TABLE resonant.assessment_questions
    DROP CONSTRAINT IF EXISTS assessment_questions_question_source_check;

ALTER TABLE resonant.assessment_questions
    ADD CONSTRAINT assessment_questions_question_source_check CHECK (
        question_source IN (
            'validated_catalog', 'validated_bank', 'ai_generated_validated',
            'deterministic_fallback'
        )
    );

ALTER TABLE resonant.assessment_attempts
    DROP CONSTRAINT IF EXISTS assessment_attempts_error_category_check;

ALTER TABLE resonant.assessment_attempts
    ADD COLUMN IF NOT EXISTS missing_dots JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS extra_dots JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS input_status TEXT NOT NULL DEFAULT 'valid',
    ADD COLUMN IF NOT EXISTS counts_for_learning BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS technical_failure_code TEXT,
    ADD COLUMN IF NOT EXISTS mapping_version TEXT NOT NULL DEFAULT 'unspecified',
    ADD COLUMN IF NOT EXISTS curriculum_version TEXT NOT NULL DEFAULT 'flutter-catalog-v1',
    ADD COLUMN IF NOT EXISTS intervention_type TEXT,
    ADD COLUMN IF NOT EXISTS feedback_type TEXT;

ALTER TABLE resonant.assessment_attempts
    ADD CONSTRAINT assessment_attempts_error_category_check CHECK (
        error_category IS NULL OR error_category IN (
            'missing_dot', 'extra_dot', 'dot_substitution',
            'multiple_dot_error', 'cell_order', 'character_confusion',
            'no_input', 'invalid_input', 'technical_input_failure',
            'prerequisite_gap', 'unknown',
            -- Retained for backward compatibility with migration 005 rows.
            'substitution'
        )
    );

ALTER TABLE resonant.assessment_attempts
    DROP CONSTRAINT IF EXISTS assessment_attempts_input_status_check;

ALTER TABLE resonant.assessment_attempts
    ADD CONSTRAINT assessment_attempts_input_status_check CHECK (
        input_status IN ('valid', 'no_input', 'invalid_input', 'technical_failure')
    );

ALTER TABLE resonant.assessment_error_summaries
    DROP CONSTRAINT IF EXISTS assessment_error_summaries_error_category_check;

ALTER TABLE resonant.assessment_error_summaries
    ADD CONSTRAINT assessment_error_summaries_error_category_check CHECK (
        error_category IN (
            'missing_dot', 'extra_dot', 'dot_substitution',
            'multiple_dot_error', 'cell_order', 'character_confusion',
            'prerequisite_gap', 'unknown', 'substitution'
        )
    );

ALTER TABLE resonant.practice_attempts
    ADD COLUMN IF NOT EXISTS session_id UUID,
    ADD COLUMN IF NOT EXISTS question_id TEXT,
    ADD COLUMN IF NOT EXISTS character_target TEXT,
    ADD COLUMN IF NOT EXISTS difficulty SMALLINT NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS expected_response JSONB,
    ADD COLUMN IF NOT EXISTS submitted_response JSONB,
    ADD COLUMN IF NOT EXISTS input_status TEXT NOT NULL DEFAULT 'valid',
    ADD COLUMN IF NOT EXISTS technical_failure_code TEXT,
    ADD COLUMN IF NOT EXISTS mapping_version TEXT NOT NULL DEFAULT 'unspecified',
    ADD COLUMN IF NOT EXISTS curriculum_version TEXT NOT NULL DEFAULT 'flutter-catalog-v1',
    ADD COLUMN IF NOT EXISTS intervention_type TEXT,
    ADD COLUMN IF NOT EXISTS feedback_type TEXT;

ALTER TABLE resonant.practice_attempts
    DROP CONSTRAINT IF EXISTS practice_attempts_input_status_check;

ALTER TABLE resonant.practice_attempts
    ADD CONSTRAINT practice_attempts_input_status_check CHECK (
        input_status IN ('valid', 'no_input', 'invalid_input', 'technical_failure')
    );

ALTER TABLE resonant.practice_attempts
    DROP CONSTRAINT IF EXISTS practice_attempts_difficulty_check;

ALTER TABLE resonant.practice_attempts
    ADD CONSTRAINT practice_attempts_difficulty_check CHECK (
        difficulty BETWEEN 1 AND 5
    );

CREATE TABLE IF NOT EXISTS resonant.ml_model_versions (
    model_version TEXT PRIMARY KEY CHECK (length(model_version) BETWEEN 1 AND 160),
    prediction_task TEXT NOT NULL CHECK (length(prediction_task) BETWEEN 1 AND 300),
    artifact_kind TEXT NOT NULL CHECK (length(artifact_kind) BETWEEN 1 AND 120),
    feature_schema_version TEXT NOT NULL CHECK (length(feature_schema_version) BETWEEN 1 AND 120),
    training_data_kind TEXT NOT NULL CHECK (training_data_kind IN
        ('consented_resonant_events', 'synthetic_demo', 'external_benchmark')),
    supported_languages TEXT[] NOT NULL,
    qualified_for_inference BOOLEAN NOT NULL DEFAULT FALSE,
    qualification JSONB NOT NULL,
    evaluation_metrics JSONB NOT NULL,
    dataset_provenance JSONB NOT NULL,
    trained_at TIMESTAMPTZ,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS resonant.ml_predictions (
    prediction_id UUID PRIMARY KEY,
    learner_id UUID NOT NULL REFERENCES resonant.learners(learner_id) ON DELETE CASCADE,
    skill_id TEXT NOT NULL CHECK (length(skill_id) BETWEEN 1 AND 160),
    language TEXT NOT NULL CHECK (language IN ('English', 'Hindi', 'Kannada')),
    prediction_task TEXT NOT NULL CHECK (length(prediction_task) BETWEEN 1 AND 300),
    probability_incorrect NUMERIC(7, 6) NOT NULL CHECK (probability_incorrect BETWEEN 0 AND 1),
    prediction_source TEXT NOT NULL CHECK (prediction_source IN
        ('qualified_model', 'cold_start_deterministic')),
    validity_status TEXT NOT NULL CHECK (validity_status IN
        ('valid', 'fallback', 'invalid')),
    model_version TEXT REFERENCES resonant.ml_model_versions(model_version),
    feature_schema_version TEXT NOT NULL,
    feature_snapshot JSONB NOT NULL,
    fallback_reason TEXT,
    prediction_latency_ms INTEGER NOT NULL DEFAULT 0 CHECK (prediction_latency_ms >= 0),
    predicted_at TIMESTAMPTZ NOT NULL,
    linked_submission_id UUID,
    observed_incorrect BOOLEAN,
    resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ml_predictions_learner_skill_time_idx
    ON resonant.ml_predictions (learner_id, skill_id, predicted_at DESC);
CREATE INDEX IF NOT EXISTS ml_predictions_unresolved_idx
    ON resonant.ml_predictions (learner_id, skill_id, predicted_at DESC)
    WHERE resolved_at IS NULL;

CREATE TABLE IF NOT EXISTS resonant.adaptive_question_instances (
    question_instance_id UUID PRIMARY KEY,
    learner_id UUID NOT NULL REFERENCES resonant.learners(learner_id) ON DELETE CASCADE,
    prediction_id UUID REFERENCES resonant.ml_predictions(prediction_id) ON DELETE SET NULL,
    skill_id TEXT NOT NULL CHECK (length(skill_id) BETWEEN 1 AND 160),
    lesson_id TEXT NOT NULL CHECK (length(lesson_id) BETWEEN 1 AND 160),
    language TEXT NOT NULL CHECK (language IN ('English', 'Hindi', 'Kannada')),
    difficulty SMALLINT NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
    question_type TEXT NOT NULL CHECK (length(question_type) BETWEEN 1 AND 80),
    question_source TEXT NOT NULL CHECK (question_source IN
        ('validated_bank', 'ai_generated_validated', 'deterministic_fallback')),
    question_version TEXT NOT NULL CHECK (length(question_version) BETWEEN 1 AND 120),
    mapping_version TEXT NOT NULL CHECK (length(mapping_version) BETWEEN 1 AND 120),
    curriculum_version TEXT NOT NULL CHECK (length(curriculum_version) BETWEEN 1 AND 120),
    question_payload JSONB NOT NULL,
    expected_response JSONB NOT NULL,
    generation_model TEXT,
    generation_failure TEXT,
    validation_status TEXT NOT NULL CHECK (validation_status IN
        ('validated', 'fallback_after_rejection')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS adaptive_questions_learner_skill_time_idx
    ON resonant.adaptive_question_instances (learner_id, skill_id, created_at DESC);

ALTER TABLE resonant.assessment_questions
    DROP CONSTRAINT IF EXISTS assessment_questions_question_instance_id_fkey;
ALTER TABLE resonant.assessment_questions
    ADD CONSTRAINT assessment_questions_question_instance_id_fkey
    FOREIGN KEY (question_instance_id)
    REFERENCES resonant.adaptive_question_instances(question_instance_id)
    ON DELETE SET NULL;

ALTER TABLE resonant.adaptive_decisions
    DROP CONSTRAINT IF EXISTS adaptive_decisions_decision_method_check;

ALTER TABLE resonant.adaptive_decisions
    ADD CONSTRAINT adaptive_decisions_decision_method_check CHECK (
        decision_method IN ('deterministic_rules', 'hybrid_ml_rules')
    );

ALTER TABLE resonant.adaptive_decisions
    ADD COLUMN IF NOT EXISTS prediction_id UUID
        REFERENCES resonant.ml_predictions(prediction_id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS question_instance_id UUID
        REFERENCES resonant.adaptive_question_instances(question_instance_id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS model_probability_incorrect NUMERIC(7, 6)
        CHECK (model_probability_incorrect IS NULL OR model_probability_incorrect BETWEEN 0 AND 1),
    ADD COLUMN IF NOT EXISTS model_version TEXT,
    ADD COLUMN IF NOT EXISTS difficulty_before SMALLINT
        CHECK (difficulty_before IS NULL OR difficulty_before BETWEEN 1 AND 5),
    ADD COLUMN IF NOT EXISTS difficulty_after SMALLINT
        CHECK (difficulty_after IS NULL OR difficulty_after BETWEEN 1 AND 5),
    ADD COLUMN IF NOT EXISTS fallback_used BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS adaptive_decisions_prediction_idx
    ON resonant.adaptive_decisions (prediction_id)
    WHERE prediction_id IS NOT NULL;

