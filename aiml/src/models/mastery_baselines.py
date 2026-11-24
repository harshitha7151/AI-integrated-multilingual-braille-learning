"""Exploratory models for observed next-attempt correctness."""

from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

from features.mastery_events import FEATURE_COLUMNS


NUMERIC_FEATURES = tuple(
    name
    for name in FEATURE_COLUMNS
    if name not in {"language", "skill_id", "question_type"}
)
CATEGORICAL_FEATURES = ("language", "skill_id", "question_type")


def _preprocessor():
    numeric = Pipeline(
        [("imputer", SimpleImputer(strategy="median")), ("scale", StandardScaler())]
    )
    categorical = Pipeline(
        [
            ("imputer", SimpleImputer(strategy="most_frequent")),
            ("one_hot", OneHotEncoder(handle_unknown="ignore")),
        ]
    )
    return ColumnTransformer(
        [("numeric", numeric, list(NUMERIC_FEATURES)), ("categorical", categorical, list(CATEGORICAL_FEATURES))]
    )


def build_mastery_models(seed: int = 20261121):
    """Return training-only preprocessing pipelines for simple model comparison."""
    return {
        "logistic_regression": Pipeline(
            [
                ("features", _preprocessor()),
                ("classifier", LogisticRegression(max_iter=2000, class_weight="balanced", random_state=seed)),
            ]
        ),
        "random_forest": Pipeline(
            [
                ("features", _preprocessor()),
                (
                    "classifier",
                    RandomForestClassifier(
                        n_estimators=300,
                        min_samples_leaf=3,
                        class_weight="balanced_subsample",
                        random_state=seed,
                        n_jobs=1,
                    ),
                ),
            ]
        ),
    }
