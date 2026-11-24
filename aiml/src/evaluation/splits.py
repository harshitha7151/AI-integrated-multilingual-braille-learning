"""Leakage-checked splits for experiments without official partitions."""

import numpy as np
from sklearn.model_selection import GroupShuffleSplit


def learner_group_split(groups, test_size: float = 0.25, seed: int = 20261120):
    """Return row indices with learner groups held out from training.

    Use official benchmark splits when a dataset provides them. This helper is
    for an unseen-learner evaluation question; it is not a temporal forecast
    split for predicting future events from known learners.
    """
    group_array = np.asarray(groups)
    if group_array.ndim != 1 or len(group_array) < 2:
        raise ValueError("groups must be a one-dimensional array with at least two rows")
    if pd_is_missing(group_array).any():
        raise ValueError("groups cannot contain missing values")
    if len(np.unique(group_array)) < 2:
        raise ValueError("at least two unique learner groups are required")
    if not 0.0 < test_size < 1.0:
        raise ValueError("test_size must be between 0 and 1")

    indices = np.arange(len(group_array))
    splitter = GroupShuffleSplit(n_splits=1, test_size=test_size, random_state=seed)
    train_indices, test_indices = next(splitter.split(indices, groups=group_array))
    train_groups = set(group_array[train_indices])
    test_groups = set(group_array[test_indices])
    if train_groups & test_groups:
        raise RuntimeError("splitter produced overlapping learner groups")
    return train_indices, test_indices


def pd_is_missing(values):
    """Numpy-level missing check without coercing IDs to strings."""
    import pandas as pd

    return pd.isna(values)
