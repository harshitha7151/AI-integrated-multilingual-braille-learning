-- Migration 006: adaptive-decision lifecycle and mastery-change reporting.
-- Existing assessment and decision rows remain valid and default to pending.

ALTER TABLE resonant.adaptive_decisions
    DROP CONSTRAINT IF EXISTS adaptive_decisions_action_check;

ALTER TABLE resonant.adaptive_decisions
    ADD CONSTRAINT adaptive_decisions_action_check CHECK (action IN
        ('advance', 'reinforce', 'remedial_practice', 'revisit_prerequisite',
         'schedule_revision', 'increase_difficulty', 'remediate', 'reassess',
         'revise'));

ALTER TABLE resonant.adaptive_decisions
    ADD COLUMN IF NOT EXISTS decision_method TEXT NOT NULL
        DEFAULT 'deterministic_rules'
        CHECK (decision_method IN ('deterministic_rules'));

ALTER TABLE resonant.adaptive_decisions
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'applied', 'completed', 'superseded'));

ALTER TABLE resonant.adaptive_decisions
    ADD COLUMN IF NOT EXISTS remediation_cycle SMALLINT NOT NULL DEFAULT 0
        CHECK (remediation_cycle BETWEEN 0 AND 100);

ALTER TABLE resonant.adaptive_decisions
    ADD COLUMN IF NOT EXISTS mastery_before NUMERIC(6, 5)
        CHECK (mastery_before IS NULL OR mastery_before BETWEEN 0 AND 1);

ALTER TABLE resonant.adaptive_decisions
    ADD COLUMN IF NOT EXISTS mastery_after NUMERIC(6, 5)
        CHECK (mastery_after IS NULL OR mastery_after BETWEEN 0 AND 1);

ALTER TABLE resonant.adaptive_decisions
    ADD COLUMN IF NOT EXISTS applied_at TIMESTAMPTZ;

ALTER TABLE resonant.adaptive_decisions
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

ALTER TABLE resonant.adaptive_decisions
    ADD COLUMN IF NOT EXISTS succeeded BOOLEAN;

CREATE INDEX IF NOT EXISTS adaptive_decisions_learner_status_idx
    ON resonant.adaptive_decisions (learner_id, status, created_at DESC);
