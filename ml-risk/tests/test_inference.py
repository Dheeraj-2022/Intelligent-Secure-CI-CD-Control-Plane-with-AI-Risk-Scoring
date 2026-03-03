"""
Unit tests for the risk scoring inference module.
"""
import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

# Allow imports from src/ without installation
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from features import extract_features, get_feature_names
from inference import (
    generate_explanation,
    generate_recommendations,
    predict_risk,
)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _make_build_context(**overrides):
    """Return a minimal, valid build context dictionary."""
    defaults = {
        "build_number": 42,
        "commit": "abc12345",
        "changed_files": 5,
        "commit_message": "feat: add health endpoint JIRA-100",
        "coverage": 85.0,
        "critical_vulns": 0,
        "test_count": 60,
        "recent_failure_rate": 0.1,
        "author_commits_30d": 25,
        "changed_files_list": ["src/main.py", "tests/test_main.py"],
    }
    defaults.update(overrides)
    return defaults


def _make_mock_model(risk_proba: float = 0.2, prediction: int = 0):
    """Return a mock sklearn model that produces deterministic output."""
    import numpy as np

    model = MagicMock()
    model.predict_proba.return_value = np.array([[1 - risk_proba, risk_proba]])
    model.predict.return_value = np.array([prediction])
    return model


# ─────────────────────────────────────────────────────────────────────────────
# Feature extraction tests
# ─────────────────────────────────────────────────────────────────────────────

class TestExtractFeatures(unittest.TestCase):

    def test_returns_all_expected_keys(self):
        ctx = _make_build_context()
        features = extract_features(ctx)
        for name in get_feature_names():
            self.assertIn(name, features, f"Missing feature: {name}")

    def test_changed_files_passed_through(self):
        features = extract_features(_make_build_context(changed_files=12))
        self.assertEqual(features["changed_files"], 12)

    def test_code_coverage_passed_through(self):
        features = extract_features(_make_build_context(coverage=73.5))
        self.assertAlmostEqual(features["code_coverage"], 73.5)

    def test_critical_vulns_passed_through(self):
        features = extract_features(_make_build_context(critical_vulns=3))
        self.assertEqual(features["critical_vulns"], 3)

    def test_commit_message_length_computed(self):
        msg = "fix: resolve null pointer exception"
        features = extract_features(_make_build_context(commit_message=msg))
        self.assertEqual(features["commit_message_length"], len(msg))

    def test_has_ticket_reference_positive(self):
        features = extract_features(
            _make_build_context(commit_message="feat: new thing JIRA-42")
        )
        self.assertEqual(features["has_ticket_reference"], 1)

    def test_has_ticket_reference_negative(self):
        features = extract_features(
            _make_build_context(commit_message="wip")
        )
        self.assertEqual(features["has_ticket_reference"], 0)

    def test_file_types_changed_counts_extensions(self):
        ctx = _make_build_context(
            changed_files_list=["a.py", "b.py", "c.yaml", "d.md"]
        )
        features = extract_features(ctx)
        self.assertEqual(features["file_types_changed"], 3)  # py, yaml, md

    def test_defaults_used_when_keys_missing(self):
        features = extract_features({"build_number": 1, "commit": "deadbeef"})
        self.assertGreaterEqual(features["changed_files"], 0)
        self.assertGreaterEqual(features["code_coverage"], 0)

    def test_feature_names_list_length(self):
        names = get_feature_names()
        self.assertEqual(len(names), 10)

    def test_feature_names_are_strings(self):
        for name in get_feature_names():
            self.assertIsInstance(name, str)


# ─────────────────────────────────────────────────────────────────────────────
# predict_risk tests
# ─────────────────────────────────────────────────────────────────────────────

class TestPredictRisk(unittest.TestCase):

    def test_low_risk_classification(self):
        model = _make_mock_model(risk_proba=0.1)
        result = predict_risk(model, _make_build_context())
        self.assertEqual(result["risk_level"], "LOW")
        self.assertLess(result["risk_score"], 0.3)

    def test_medium_risk_classification(self):
        model = _make_mock_model(risk_proba=0.5)
        result = predict_risk(model, _make_build_context())
        self.assertEqual(result["risk_level"], "MEDIUM")

    def test_high_risk_classification(self):
        model = _make_mock_model(risk_proba=0.85, prediction=1)
        result = predict_risk(model, _make_build_context(critical_vulns=2))
        self.assertEqual(result["risk_level"], "HIGH")
        self.assertGreaterEqual(result["risk_score"], 0.7)

    def test_result_contains_required_keys(self):
        model = _make_mock_model()
        result = predict_risk(model, _make_build_context())
        required = [
            "risk_score",
            "risk_level",
            "risk_emoji",
            "predicted_failure",
            "predicted_failure_reason",
            "top_contributing_features",
            "all_features",
            "recommended_actions",
        ]
        for key in required:
            self.assertIn(key, result)

    def test_risk_score_is_float_in_range(self):
        model = _make_mock_model(risk_proba=0.42)
        result = predict_risk(model, _make_build_context())
        self.assertIsInstance(result["risk_score"], float)
        self.assertGreaterEqual(result["risk_score"], 0.0)
        self.assertLessEqual(result["risk_score"], 1.0)

    def test_predicted_failure_is_bool(self):
        model = _make_mock_model(prediction=1)
        result = predict_risk(model, _make_build_context())
        self.assertIsInstance(result["predicted_failure"], bool)

    def test_recommendations_is_nonempty_list(self):
        model = _make_mock_model()
        result = predict_risk(model, _make_build_context())
        self.assertIsInstance(result["recommended_actions"], list)
        self.assertGreater(len(result["recommended_actions"]), 0)

    def test_emoji_green_for_low_risk(self):
        model = _make_mock_model(risk_proba=0.1)
        result = predict_risk(model, _make_build_context())
        self.assertEqual(result["risk_emoji"], "🟢")

    def test_emoji_yellow_for_medium_risk(self):
        model = _make_mock_model(risk_proba=0.5)
        result = predict_risk(model, _make_build_context())
        self.assertEqual(result["risk_emoji"], "🟡")

    def test_emoji_red_for_high_risk(self):
        model = _make_mock_model(risk_proba=0.9)
        result = predict_risk(model, _make_build_context())
        self.assertEqual(result["risk_emoji"], "🔴")


# ─────────────────────────────────────────────────────────────────────────────
# Explanation & recommendation tests
# ─────────────────────────────────────────────────────────────────────────────

class TestGenerateExplanation(unittest.TestCase):

    def _features(self, **overrides):
        base = {
            "critical_vulns": 0,
            "code_coverage": 90.0,
            "changed_files": 5,
            "commit_message_length": 40,
            "test_count": 60,
        }
        base.update(overrides)
        return base

    def test_no_issues_returns_ok_message(self):
        msg = generate_explanation(self._features(), "LOW")
        self.assertIn("acceptable", msg.lower())

    def test_critical_vulns_mentioned(self):
        msg = generate_explanation(self._features(critical_vulns=2), "HIGH")
        self.assertIn("vulnerabilit", msg.lower())

    def test_low_coverage_mentioned(self):
        msg = generate_explanation(self._features(code_coverage=55.0), "HIGH")
        self.assertIn("coverage", msg.lower())

    def test_large_changeset_mentioned(self):
        msg = generate_explanation(self._features(changed_files=20), "MEDIUM")
        self.assertIn("changeset", msg.lower())

    def test_short_commit_message_mentioned(self):
        msg = generate_explanation(self._features(commit_message_length=5), "MEDIUM")
        self.assertIn("commit", msg.lower())

    def test_multiple_issues_joined(self):
        msg = generate_explanation(
            self._features(critical_vulns=1, code_coverage=50.0), "HIGH"
        )
        self.assertIn(";", msg)


class TestGenerateRecommendations(unittest.TestCase):

    def _features(self, **overrides):
        base = {
            "critical_vulns": 0,
            "code_coverage": 90.0,
            "changed_files": 5,
            "test_count": 60,
        }
        base.update(overrides)
        return base

    def test_clean_build_returns_proceed_recommendation(self):
        recs = generate_recommendations(self._features(), 0.1)
        combined = " ".join(recs).lower()
        self.assertIn("proceed", combined)

    def test_critical_vulns_triggers_security_recommendation(self):
        recs = generate_recommendations(self._features(critical_vulns=1), 0.5)
        combined = " ".join(recs).lower()
        self.assertTrue(
            "vulnerab" in combined or "critical" in combined,
            f"Expected security recommendation in: {recs}",
        )

    def test_low_coverage_triggers_coverage_recommendation(self):
        recs = generate_recommendations(self._features(code_coverage=60.0), 0.4)
        combined = " ".join(recs).lower()
        self.assertIn("coverage", combined)

    def test_high_risk_score_triggers_review_recommendation(self):
        recs = generate_recommendations(self._features(), 0.85)
        combined = " ".join(recs).lower()
        self.assertIn("review", combined)

    def test_large_pr_triggers_split_recommendation(self):
        recs = generate_recommendations(self._features(changed_files=25), 0.3)
        combined = " ".join(recs).lower()
        self.assertIn("smaller", combined)

    def test_returns_list(self):
        recs = generate_recommendations(self._features(), 0.2)
        self.assertIsInstance(recs, list)


# ─────────────────────────────────────────────────────────────────────────────
# Integration-style: end-to-end with mock model
# ─────────────────────────────────────────────────────────────────────────────

class TestInferenceEndToEnd(unittest.TestCase):

    def test_full_pipeline_low_risk_build(self):
        """A healthy build should produce LOW risk and no blocking recs."""
        model = _make_mock_model(risk_proba=0.05)
        ctx = _make_build_context(
            coverage=92.0,
            critical_vulns=0,
            changed_files=3,
            commit_message="fix: correct off-by-one error in pagination JIRA-200",
        )
        result = predict_risk(model, ctx)
        self.assertEqual(result["risk_level"], "LOW")
        self.assertFalse(result["predicted_failure"])

    def test_full_pipeline_high_risk_build(self):
        """A problematic build should produce HIGH risk with recommendations."""
        model = _make_mock_model(risk_proba=0.92, prediction=1)
        ctx = _make_build_context(
            coverage=45.0,
            critical_vulns=3,
            changed_files=30,
            commit_message="wip",
        )
        result = predict_risk(model, ctx)
        self.assertEqual(result["risk_level"], "HIGH")
        self.assertTrue(result["predicted_failure"])
        # Should have multiple actionable recommendations
        self.assertGreaterEqual(len(result["recommended_actions"]), 2)

    def test_output_is_json_serialisable(self):
        """Risk report must be serialisable to JSON (for pipeline artefact)."""
        model = _make_mock_model(risk_proba=0.55)
        result = predict_risk(model, _make_build_context())
        try:
            serialised = json.dumps(result)
            self.assertIsInstance(serialised, str)
        except TypeError as exc:
            self.fail(f"Risk result is not JSON-serialisable: {exc}")


if __name__ == "__main__":
    unittest.main()
