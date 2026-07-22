"""Backward-compatible import wrapper.

New code should import from recoverysense_ml.features.
"""
from recoverysense_ml.features import extract_window_features

__all__ = ["extract_window_features"]
