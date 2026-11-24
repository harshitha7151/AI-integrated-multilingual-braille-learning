"""Reproducible baseline and Random Forest pipelines for answer prediction."""

from __future__ import annotations

from sklearn.compose import ColumnTransformer
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

from features.assistments_history import CATEGORICAL_FEATURES, NUMERIC_FEATURES


def _preprocessor(*, scale_numeric: bool) -> ColumnTransformer:
    numeric_steps = [("impute", SimpleImputer(strategy="median"))]
    if scale_numeric:
        numeric_steps.append(("scale", StandardScaler()))
    return ColumnTransformer(
        transformers=[
            ("numeric", Pipeline(numeric_steps), list(NUMERIC_FEATURES)),
            (
                "categorical",
                Pipeline(
                    [
                        ("impute", SimpleImputer(strategy="most_frequent")),
                        (
                            "one_hot",
                            OneHotEncoder(handle_unknown="ignore", sparse_output=True),
                        ),
                    ]
                ),
                list(CATEGORICAL_FEATURES),
            ),
        ],
        remainder="drop",
    )


def build_models(seed: int) -> dict[str, Pipeline]:
    """Return fixed, predeclared models; the held-out test set is not tuned."""

    return {
        "majority_baseline": Pipeline(
            [
                ("preprocess", _preprocessor(scale_numeric=False)),
                ("model", DummyClassifier(strategy="prior", random_state=seed)),
            ]
        ),
        "logistic_regression": Pipeline(
            [
                ("preprocess", _preprocessor(scale_numeric=True)),
                (
                    "model",
                    LogisticRegression(
                        max_iter=600,
                        class_weight="balanced",
                        random_state=seed,
                    ),
                ),
            ]
        ),
        "random_forest": Pipeline(
            [
                ("preprocess", _preprocessor(scale_numeric=False)),
                (
                    "model",
                    RandomForestClassifier(
                        n_estimators=160,
                        max_depth=16,
                        min_samples_leaf=12,
                        max_features="sqrt",
                        class_weight="balanced_subsample",
                        n_jobs=-1,
                        random_state=seed,
                    ),
                ),
            ]
        ),
    }


def random_forest_feature_importance(fitted_pipeline: Pipeline):
    """Return transformed feature names and impurity-based importance values."""

    preprocessor = fitted_pipeline.named_steps["preprocess"]
    model = fitted_pipeline.named_steps["model"]
    names = preprocessor.get_feature_names_out()
    values = model.feature_importances_
    return names, values
