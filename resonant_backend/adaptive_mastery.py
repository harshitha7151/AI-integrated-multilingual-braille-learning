"""Configurable Bayesian Knowledge Tracing and deterministic review intervals."""

from __future__ import annotations

from dataclasses import dataclass
import os


@dataclass(frozen=True)
class BKTParameters:
    prior_knowledge: float = 0.2
    learning_probability: float = 0.12
    guess_probability: float = 0.2
    slip_probability: float = 0.1

    def __post_init__(self):
        if not 0.0 <= self.prior_knowledge <= 1.0:
            raise ValueError("prior_knowledge must be between 0 and 1")
        if not 0.0 <= self.learning_probability < 1.0:
            raise ValueError("learning_probability must be in [0, 1)")
        if not 0.0 < self.guess_probability < 1.0:
            raise ValueError("guess_probability must be between 0 and 1")
        if not 0.0 < self.slip_probability < 1.0:
            raise ValueError("slip_probability must be between 0 and 1")

    @classmethod
    def from_environment(cls):
        return cls(
            prior_knowledge=float(os.getenv("RESONANT_BKT_PRIOR", "0.2")),
            learning_probability=float(os.getenv("RESONANT_BKT_LEARN", "0.12")),
            guess_probability=float(os.getenv("RESONANT_BKT_GUESS", "0.2")),
            slip_probability=float(os.getenv("RESONANT_BKT_SLIP", "0.1")),
        )


def update_mastery(prior: float, correct: bool, parameters: BKTParameters) -> float:
    """Apply one BKT observation, followed by the learning transition."""
    if not 0.0 <= prior <= 1.0:
        raise ValueError("prior mastery must be between 0 and 1")
    likelihood_known = 1.0 - parameters.slip_probability if correct else parameters.slip_probability
    likelihood_unknown = parameters.guess_probability if correct else 1.0 - parameters.guess_probability
    denominator = prior * likelihood_known + (1.0 - prior) * likelihood_unknown
    posterior = prior if denominator == 0 else prior * likelihood_known / denominator
    learned = posterior + (1.0 - posterior) * parameters.learning_probability
    return min(1.0, max(0.0, learned))


def review_interval_days(mastery: float, correct: bool) -> int:
    """Schedule an error promptly and space successful reviews by mastery."""
    if not 0.0 <= mastery <= 1.0:
        raise ValueError("mastery must be between 0 and 1")
    if not correct:
        return 0
    if mastery >= 0.85:
        return 14
    if mastery >= 0.65:
        return 7
    if mastery >= 0.45:
        return 3
    return 1


def _sql_bkt_expression(prior: str, correct: bool, parameters: BKTParameters) -> str:
    """Return an SQL expression equivalent to ``update_mastery``."""
    guess = repr(parameters.guess_probability)
    slip = repr(parameters.slip_probability)
    learn = repr(parameters.learning_probability)
    likelihood_known = f"(1 - {slip})" if correct else slip
    likelihood_unknown = guess if correct else f"(1 - {guess})"
    posterior = (
        f"(({prior}) * {likelihood_known}) / "
        f"((({prior}) * {likelihood_known}) + (1 - ({prior})) * {likelihood_unknown})"
    )
    return f"(({posterior}) + (1 - ({posterior})) * {learn})"


def sql_mastery_update_expression(parameters: BKTParameters) -> str:
    """Build the atomic conflict-update expression using the stored prior."""
    prior = "resonant.skill_progress.mastery"
    return (
        "CASE WHEN EXCLUDED.correct_count = 1 THEN "
        f"{_sql_bkt_expression(prior, True, parameters)} ELSE "
        f"{_sql_bkt_expression(prior, False, parameters)} END"
    )
