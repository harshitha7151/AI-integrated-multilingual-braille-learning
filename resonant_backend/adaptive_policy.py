"""Explainable selection signals for supported adaptive exercises.

These functions estimate decision value from persisted response evidence; they
are policy calculations, not validated predictions of learning or forgetting.
"""

from __future__ import annotations

from datetime import datetime, timezone
import math

from adaptive_mastery import BKTParameters, update_mastery


def binary_entropy(probability: float) -> float:
    if not 0.0 <= probability <= 1.0:
        raise ValueError("probability must be between 0 and 1")
    if probability in (0.0, 1.0):
        return 0.0
    return -probability * math.log2(probability) - (1 - probability) * math.log2(1 - probability)


def expected_information_gain(
    mastery: float,
    parameters: BKTParameters,
) -> float:
    """Expected entropy reduction from one binary response under BKT emissions."""
    if not 0.0 <= mastery <= 1.0:
        raise ValueError("mastery must be between 0 and 1")
    p_correct = mastery * (1 - parameters.slip_probability) + (
        1 - mastery
    ) * parameters.guess_probability
    posterior_correct = update_mastery_without_learning(mastery, True, parameters)
    posterior_incorrect = update_mastery_without_learning(mastery, False, parameters)
    expected_entropy = (
        p_correct * binary_entropy(posterior_correct)
        + (1 - p_correct) * binary_entropy(posterior_incorrect)
    )
    return max(0.0, binary_entropy(mastery) - expected_entropy)


def update_mastery_without_learning(
    mastery: float,
    correct: bool,
    parameters: BKTParameters,
) -> float:
    """Bayesian observation posterior, before BKT's learning transition."""
    likelihood_known = 1 - parameters.slip_probability if correct else parameters.slip_probability
    likelihood_unknown = parameters.guess_probability if correct else 1 - parameters.guess_probability
    denominator = mastery * likelihood_known + (1 - mastery) * likelihood_unknown
    return mastery if denominator == 0 else mastery * likelihood_known / denominator


def forgetting_risk(
    mastery: float,
    days_since_practice: float,
    *,
    half_life_days: float = 14.0,
) -> float:
    """Heuristic risk proxy: mastery decays exponentially after practice."""
    if not 0 <= mastery <= 1 or days_since_practice < 0 or half_life_days <= 0:
        raise ValueError("invalid_forgetting_risk_inputs")
    retained = mastery * 2 ** (-days_since_practice / half_life_days)
    return min(1.0, max(0.0, 1 - retained))


def rank_supported_skills(
    candidate_skills: list[str],
    progress_rows: list[dict],
    error_rows: list[dict],
    *,
    now: datetime | None = None,
    parameters: BKTParameters | None = None,
) -> list[dict]:
    """Rank only caller-provided, curriculum-eligible skills deterministically."""
    now = now or datetime.now(timezone.utc)
    parameters = parameters or BKTParameters.from_environment()
    progress = {str(row["skill_id"]): row for row in progress_rows}
    errors: dict[str, int] = {}
    for row in error_rows:
        skill = str(row.get("skill_id") or "")
        errors[skill] = errors.get(skill, 0) + int(row.get("error_count") or 0)

    scored = []
    for skill_id in dict.fromkeys(candidate_skills):
        row = progress.get(skill_id)
        mastery = float(row.get("mastery", parameters.prior_knowledge)) if row else parameters.prior_knowledge
        # Existing/test rows may predate the attempts projection; their stored
        # skill_progress row itself is evidence of prior practice.
        attempts = int(row.get("attempts") or 1) if row else 0
        updated = row.get("updated_at") if row else None
        if isinstance(updated, str):
            try:
                updated = datetime.fromisoformat(updated.replace("Z", "+00:00"))
            except ValueError:
                updated = None
        if isinstance(updated, datetime) and updated.tzinfo is None:
            updated = updated.replace(tzinfo=timezone.utc)
        elapsed = (
            max(0.0, (now - updated).total_seconds() / 86400.0)
            if attempts and isinstance(updated, datetime)
            else None
        )
        risk = forgetting_risk(mastery, elapsed) if elapsed is not None else 0.0
        review_at = row.get("next_review_at") if row else None
        if isinstance(review_at, str):
            try:
                review_at = datetime.fromisoformat(review_at.replace("Z", "+00:00"))
            except ValueError:
                review_at = None
        if isinstance(review_at, datetime) and review_at.tzinfo is None:
            review_at = review_at.replace(tzinfo=timezone.utc)
        due = bool(attempts and isinstance(review_at, datetime) and review_at <= now)
        information_gain = expected_information_gain(mastery, parameters)
        error_count = errors.get(skill_id, 0)
        # A due review and measured recurring errors take precedence; entropy
        # gain breaks ties among uncertain, eligible skills.
        score = (2.0 if due else 0.0) + min(error_count, 5) * 0.25 + risk + information_gain
        scored.append({
            "skill_id": skill_id,
            "score": score,
            "mastery": mastery,
            "attempts": attempts,
            "review_due": due,
            "forgetting_risk_estimate": risk if attempts else None,
            "information_gain_bits": information_gain,
            "error_count": error_count,
        })
    return sorted(scored, key=lambda item: (-item["score"], item["skill_id"]))


def contextual_bandit_ranking(
    ranked_candidates: list[dict],
    prior_decisions: list[dict],
    *,
    exploration: float = 0.25,
    minimum_rewards: int = 5,
) -> list[dict] | None:
    """LinUCB over completed, persisted recommendation outcomes.

    Prior records must contain the selection-context snapshot written by
    ``rank_supported_skills`` and a genuine ``succeeded`` outcome. Returns
    ``None`` until enough observations exist so callers can keep the safe
    deterministic information-gain/forgetting policy.
    """
    dimension = 6
    matrix = [[float(i == j) for j in range(dimension)] for i in range(dimension)]
    target = [0.0] * dimension
    samples = 0
    for decision in prior_decisions:
        evidence = decision.get("evidence")
        if not isinstance(evidence, dict) or not isinstance(decision.get("succeeded"), bool):
            continue
        selected = evidence.get("selected_skill_for_next_exercise")
        eligible = evidence.get("eligible_skill_scores")
        selected_id = selected.get("skill_id") if isinstance(selected, dict) else None
        if not isinstance(selected_id, str) or not isinstance(eligible, list):
            continue
        row = next(
            (item for item in eligible if isinstance(item, dict) and item.get("skill_id") == selected_id),
            None,
        )
        if row is None:
            continue
        features = _context_features(row)
        reward = float(decision["succeeded"])
        for i in range(dimension):
            target[i] += reward * features[i]
            for j in range(dimension):
                matrix[i][j] += features[i] * features[j]
        samples += 1
    if samples < minimum_rewards:
        return None

    result = []
    for candidate in ranked_candidates:
        features = _context_features(candidate)
        coefficients = _solve(matrix, target)
        uncertainty = _solve(matrix, features)
        mean_reward = sum(a * b for a, b in zip(features, coefficients))
        variance = max(0.0, sum(a * b for a, b in zip(features, uncertainty)))
        result.append({
            **candidate,
            "bandit_score": mean_reward + exploration * math.sqrt(variance),
            "bandit_observation_count": samples,
        })
    return sorted(
        result,
        key=lambda item: (-item["bandit_score"], -item["score"], item["skill_id"]),
    )


def _context_features(row: dict) -> list[float]:
    risk = row.get("forgetting_risk_estimate")
    return [
        1.0,
        float(row.get("mastery") or 0.0),
        float(row.get("information_gain_bits") or 0.0),
        float(risk or 0.0),
        float(bool(row.get("review_due"))),
        min(1.0, max(0.0, float(row.get("error_count") or 0) / 5.0)),
    ]


def _solve(matrix: list[list[float]], vector: list[float]) -> list[float]:
    """Solve a small positive-definite system by pivoted Gaussian elimination."""
    size = len(vector)
    augmented = [matrix[row][:] + [vector[row]] for row in range(size)]
    for column in range(size):
        pivot = max(range(column, size), key=lambda row: abs(augmented[row][column]))
        if abs(augmented[pivot][column]) < 1e-12:
            raise ValueError("bandit_context_matrix_singular")
        augmented[column], augmented[pivot] = augmented[pivot], augmented[column]
        divisor = augmented[column][column]
        augmented[column] = [value / divisor for value in augmented[column]]
        for row in range(size):
            if row == column:
                continue
            factor = augmented[row][column]
            augmented[row] = [
                value - factor * pivot_value
                for value, pivot_value in zip(augmented[row], augmented[column])
            ]
    return [augmented[row][-1] for row in range(size)]
