"""Text-only intent classification baselines; no Braille encoding logic."""

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.calibration import CalibratedClassifierCV
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.svm import LinearSVC


def build_intent_models(seed: int = 20261120) -> dict[str, Pipeline]:
    """Return fixed, reproducible baselines with vectorizers fit on train only."""
    def vectorizer() -> TfidfVectorizer:
        return TfidfVectorizer(
            lowercase=True,
            strip_accents="unicode",
            ngram_range=(1, 2),
            min_df=1,
            sublinear_tf=True,
        )

    return {
        "tfidf_logistic_regression": Pipeline(
            [
                ("tfidf", vectorizer()),
                (
                    "classifier",
                    LogisticRegression(
                        C=4.0,
                        max_iter=2000,
                        random_state=seed,
                        solver="lbfgs",
                    ),
                ),
            ]
        ),
        "tfidf_linear_svm": Pipeline(
            [("tfidf", vectorizer()), ("classifier", LinearSVC(C=1.0, random_state=seed))]
        ),
        "tfidf_calibrated_linear_svm": Pipeline(
            [
                ("tfidf", vectorizer()),
                (
                    "classifier",
                    CalibratedClassifierCV(
                        estimator=LinearSVC(C=1.0, random_state=seed),
                        method="sigmoid",
                        cv=3,
                    ),
                ),
            ]
        ),
    }
