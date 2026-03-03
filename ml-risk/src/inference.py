"""
Risk scoring inference for CI/CD pipeline
"""
import argparse
import json
import joblib
import numpy as np
from pathlib import Path
from features import extract_features, get_feature_names

def load_model(model_path='models/risk_model.pkl'):
    """Load trained model"""
    return joblib.load(model_path)

def predict_risk(model, build_context):
    """
    Predict risk score for a build
    
    Args:
        model: Trained model
        build_context: Dictionary with build metadata
        
    Returns:
        Dictionary with risk assessment
    """
    # Extract features
    features = extract_features(build_context)
    
    # Prepare feature vector
    feature_names = get_feature_names()
    X = np.array([[features.get(f, 0) for f in feature_names]])
    
    # Predict
    risk_score = float(model.predict_proba(X)[0, 1])
    prediction = int(model.predict(X)[0])
    
    # Determine risk level
    if risk_score < 0.3:
        risk_level = 'LOW'
        color = '🟢'
    elif risk_score < 0.7:
        risk_level = 'MEDIUM'
        color = '🟡'
    else:
        risk_level = 'HIGH'
        color = '🔴'
    
    # Get feature contributions (simplified - using feature values as proxy)
    feature_contributions = [
        {'feature': name, 'value': features.get(name, 0)}
        for name in feature_names
    ]
    feature_contributions.sort(key=lambda x: abs(x['value']), reverse=True)
    
    # Generate explanation
    top_features = feature_contributions[:3]
    explanation = generate_explanation(features, risk_level)
    
    result = {
        'risk_score': round(risk_score, 3),
        'risk_level': risk_level,
        'risk_emoji': color,
        'predicted_failure': bool(prediction),
        'predicted_failure_reason': explanation,
        'top_contributing_features': top_features,
        'all_features': features,
        'recommended_actions': generate_recommendations(features, risk_score)
    }
    
    return result

def generate_explanation(features, risk_level):
    """Generate human-readable explanation"""
    reasons = []
    
    if features['critical_vulns'] > 0:
        reasons.append(f"Critical vulnerabilities detected ({features['critical_vulns']})")
    
    if features['code_coverage'] < 70:
        reasons.append(f"Low code coverage ({features['code_coverage']:.1f}%)")
    
    if features['changed_files'] > 15:
        reasons.append(f"Large changeset ({features['changed_files']} files)")
    
    if features['commit_message_length'] < 20:
        reasons.append("Insufficient commit message")
    
    if features['test_count'] < 30:
        reasons.append(f"Low test count ({features['test_count']})")
    
    if not reasons:
        return "All metrics within acceptable ranges"
    
    return "; ".join(reasons)

def generate_recommendations(features, risk_score):
    """Generate actionable recommendations"""
    recommendations = []
    
    if features['critical_vulns'] > 0:
        recommendations.append("🔒 Address critical vulnerabilities before merging")
    
    if features['code_coverage'] < 80:
        recommendations.append(f"📊 Increase code coverage to 80% (current: {features['code_coverage']:.1f}%)")
    
    if features['test_count'] < 50:
        recommendations.append("🧪 Add more unit tests to improve reliability")
    
    if features['changed_files'] > 20:
        recommendations.append("✂️ Consider breaking this change into smaller PRs")
    
    if risk_score > 0.7:
        recommendations.append("⚠️ Request additional code review due to high risk")
    
    if not recommendations:
        recommendations.append("✅ No specific recommendations - proceed with deployment")
    
    return recommendations

def main():
    parser = argparse.ArgumentParser(description='Predict CI/CD pipeline risk')
    parser.add_argument('--build-number', type=int, required=True)
    parser.add_argument('--commit', type=str, required=True)
    parser.add_argument('--changed-files', type=int, default=5)
    parser.add_argument('--commit-message', type=str, default='')
    parser.add_argument('--coverage', type=float, default=0)
    parser.add_argument('--critical-vulns', type=int, default=0)
    parser.add_argument('--test-count', type=int, default=50)
    parser.add_argument('--output', type=str, default='risk-score.json')
    parser.add_argument('--model-path', type=str, default='models/risk_model.pkl')
    
    args = parser.parse_args()
    
    # Build context
    build_context = {
        'build_number': args.build_number,
        'commit': args.commit,
        'changed_files': args.changed_files,
        'commit_message': args.commit_message,
        'coverage': args.coverage,
        'critical_vulns': args.critical_vulns,
        'test_count': args.test_count,
        'recent_failure_rate': 0.1,  # Would query from database
        'author_commits_30d': 20,  # Would query from git
        'changed_files_list': []  # Would get from git diff
    }
    
    # Load model and predict
    model = load_model(args.model_path)
    result = predict_risk(model, build_context)
    
    # Save result
    with open(args.output, 'w') as f:
        json.dump(result, f, indent=2)
    
    # Print summary
    print(f"\n{result['risk_emoji']} Risk Assessment: {result['risk_level']}")
    print(f"Risk Score: {result['risk_score']}")
    print(f"Predicted Failure: {result['predicted_failure']}")
    print(f"\nReason: {result['predicted_failure_reason']}")
    print("\nRecommendations:")
    for rec in result['recommended_actions']:
        print(f"  {rec}")
    
    return result

if __name__ == '__main__':
    main()