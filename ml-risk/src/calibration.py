"""
Probability calibration utilities for the risk scoring model.

Provides tools to:
- Evaluate calibration quality (reliability diagrams, Brier score)
- Recalibrate an existing model using Platt scaling or isotonic regression
- Persist and load calibrated wrappers
"""
import numpy as np
import json
from pathlib import Path
from typing import Tuple, Dict, Any

import joblib
from sklearn.calibration import CalibratedClassifierCV, calibration_curve
from sklearn.metrics import brier_score_loss
from sklearn.model_selection import cross_val_predict


# ---------------------------------------------------------------------------
# Evaluation helpers
# ---------------------------------------------------------------------------

def compute_brier_score(y_true: np.ndarray, y_prob: np.ndarray) -> float:
    """
    Compute Brier score (lower is better; 0 = perfect, 1 = worst).

    Args:
        y_true: True binary labels (0/1).
        y_prob: Predicted probabilities for the positive class.

    Returns:
        Brier score as a float.
    """
    return float(brier_score_loss(y_true, y_prob))


def reliability_diagram_data(
    y_true: np.ndarray,
    y_prob: np.ndarray,
    n_bins: int = 10,
) -> Dict[str, Any]:
    """
    Compute data for a reliability (calibration) diagram.

    Args:
        y_true: True binary labels.
        y_prob: Predicted probabilities for the positive class.
        n_bins: Number of calibration bins.

    Returns:
        Dictionary with keys:
            - ``fraction_of_positives``: observed positive rate per bin
            - ``mean_predicted_value``: average predicted probability per bin
            - ``brier_score``: overall Brier score
            - ``calibration_error``: mean absolute calibration error
    """
    fraction_of_positives, mean_predicted_value = calibration_curve(
        y_true, y_prob, n_bins=n_bins, strategy="uniform"
    )

    calibration_error = float(
        np.mean(np.abs(fraction_of_positives - mean_predicted_value))
    )

    return {
        "fraction_of_positives": fraction_of_positives.tolist(),
        "mean_predicted_value": mean_predicted_value.tolist(),
        "brier_score": compute_brier_score(y_true, y_prob),
        "calibration_error": calibration_error,
    }


def expected_calibration_error(
    y_true: np.ndarray,
    y_prob: np.ndarray,
    n_bins: int = 10,
) -> float:
    """
    Compute Expected Calibration Error (ECE).

    ECE is the weighted average absolute difference between
    predicted probabilities and observed frequencies across bins.

    Args:
        y_true: True binary labels.
        y_prob: Predicted probabilities for the positive class.
        n_bins: Number of equal-width bins.

    Returns:
        ECE as a float in [0, 1].
    """
    n = len(y_true)
    ece = 0.0
    bins = np.linspace(0.0, 1.0, n_bins + 1)

    for low, high in zip(bins[:-1], bins[1:]):
        mask = (y_prob >= low) & (y_prob < high)
        if not mask.any():
            continue
        bin_weight = mask.sum() / n
        bin_accuracy = float(y_true[mask].mean())
        bin_confidence = float(y_prob[mask].mean())
        ece += bin_weight * abs(bin_accuracy - bin_confidence)

    return ece


# ---------------------------------------------------------------------------
# Recalibration
# ---------------------------------------------------------------------------

def recalibrate_model(
    base_model,
    X_cal: np.ndarray,
    y_cal: np.ndarray,
    method: str = "sigmoid",
    cv: int = 5,
):
    """
    Wrap a fitted base model with a calibration layer.

    Args:
        base_model: An already-fitted sklearn estimator.
        X_cal: Calibration features (held-out set or cross-val).
        y_cal: Calibration labels.
        method: ``"sigmoid"`` (Platt) or ``"isotonic"``.
        cv: If ``"prefit"``, calibrates on (X_cal, y_cal) directly.
            Otherwise treated as number of CV folds for cross_val_predict.

    Returns:
        A fitted ``CalibratedClassifierCV`` instance.
    """
    calibrated = CalibratedClassifierCV(
        estimator=base_model,
        method=method,
        cv="prefit",
    )
    calibrated.fit(X_cal, y_cal)
    return calibrated


def evaluate_calibration(
    model,
    X: np.ndarray,
    y: np.ndarray,
    n_bins: int = 10,
) -> Dict[str, Any]:
    """
    Full calibration evaluation of a fitted model.

    Args:
        model: Fitted sklearn estimator with ``predict_proba``.
        X: Feature matrix.
        y: True labels.
        n_bins: Bins for reliability diagram.

    Returns:
        Dictionary with brier_score, ece, reliability_diagram data.
    """
    y_prob = model.predict_proba(X)[:, 1]

    diagram = reliability_diagram_data(y, y_prob, n_bins=n_bins)
    ece = expected_calibration_error(y, y_prob, n_bins=n_bins)

    return {
        "brier_score": diagram["brier_score"],
        "ece": ece,
        "calibration_error_mean_abs": diagram["calibration_error"],
        "reliability_diagram": {
            "fraction_of_positives": diagram["fraction_of_positives"],
            "mean_predicted_value": diagram["mean_predicted_value"],
        },
    }


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

def save_calibration_report(
    report: Dict[str, Any],
    output_path: str = "models/calibration_report.json",
) -> None:
    """
    Save calibration evaluation report to a JSON file.

    Args:
        report: Calibration metrics dictionary.
        output_path: Destination file path.
    """
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(report, f, indent=2)
    print(f"Calibration report saved to {output_path}")


def load_calibration_report(path: str = "models/calibration_report.json") -> Dict[str, Any]:
    """Load a previously saved calibration report."""
    with open(path) as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# CLI entry-point
# ---------------------------------------------------------------------------

def main() -> None:
    """
    Evaluate and optionally recalibrate the saved risk model.

    Usage::

        python calibration.py [--recalibrate] [--method sigmoid|isotonic]
    """
    import argparse
    import pandas as pd
    from sklearn.model_selection import train_test_split

    parser = argparse.ArgumentParser(description="Model calibration utilities")
    parser.add_argument("--model-path", default="models/risk_model.pkl")
    parser.add_argument("--data-path", default="data/synthetic_dataset.csv")
    parser.add_argument("--recalibrate", action="store_true")
    parser.add_argument("--method", choices=["sigmoid", "isotonic"], default="sigmoid")
    parser.add_argument("--output-model", default="models/risk_model_calibrated.pkl")
    parser.add_argument("--output-report", default="models/calibration_report.json")
    args = parser.parse_args()

    # Load data
    df = pd.read_csv(args.data_path)
    feature_cols = [
        "changed_files", "commit_message_length", "hour_of_day",
        "day_of_week", "code_coverage", "critical_vulns",
        "test_count", "build_history_failures", "file_types_changed",
        "author_experience",
    ]
    X = df[feature_cols].values
    y = df["pipeline_failed"].values

    # Hold-out calibration set
    X_train, X_cal, y_train, y_cal = train_test_split(
        X, y, test_size=0.2, random_state=0, stratify=y
    )

    # Load model
    model = joblib.load(args.model_path)
    print(f"Loaded model from {args.model_path}")

    # Evaluate current calibration
    print("\n── Before recalibration ──")
    report_before = evaluate_calibration(model, X_cal, y_cal)
    print(f"  Brier Score : {report_before['brier_score']:.4f}")
    print(f"  ECE         : {report_before['ece']:.4f}")

    if args.recalibrate:
        recal_model = recalibrate_model(model, X_cal, y_cal, method=args.method)
        print(f"\n── After recalibration ({args.method}) ──")
        report_after = evaluate_calibration(recal_model, X_cal, y_cal)
        print(f"  Brier Score : {report_after['brier_score']:.4f}")
        print(f"  ECE         : {report_after['ece']:.4f}")

        joblib.dump(recal_model, args.output_model)
        print(f"\nRecalibrated model saved to {args.output_model}")

        save_calibration_report(report_after, args.output_report)
    else:
        save_calibration_report(report_before, args.output_report)


if __name__ == "__main__":
    main()
