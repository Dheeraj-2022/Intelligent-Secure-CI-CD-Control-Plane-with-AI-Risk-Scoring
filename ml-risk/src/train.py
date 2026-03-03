"""
Train risk scoring model
"""
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, roc_auc_score, roc_curve
from sklearn.calibration import CalibratedClassifierCV
import joblib
import json
from pathlib import Path

def train_model(data_path='data/synthetic_dataset.csv', output_dir='models'):
    """
    Train and save risk scoring model
    
    Args:
        data_path: Path to training data CSV
        output_dir: Directory to save model artifacts
    """
    # Load data
    df = pd.read_csv(data_path)
    
    # Prepare features and target
    feature_cols = [
        'changed_files', 'commit_message_length', 'hour_of_day',
        'day_of_week', 'code_coverage', 'critical_vulns',
        'test_count', 'build_history_failures', 'file_types_changed',
        'author_experience'
    ]
    
    X = df[feature_cols]
    y = df['pipeline_failed']
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    
    print(f"Training set: {len(X_train)} samples")
    print(f"Test set: {len(X_test)} samples")
    print(f"Failure rate - Train: {y_train.mean():.2%}, Test: {y_test.mean():.2%}")
    
    # Train base model
    print("\nTraining Gradient Boosting Classifier...")
    base_model = GradientBoostingClassifier(
        n_estimators=100,
        learning_rate=0.1,
        max_depth=5,
        random_state=42
    )
    
    # Calibrate probabilities
    model = CalibratedClassifierCV(base_model, cv=5, method='sigmoid')
    model.fit(X_train, y_train)
    
    # Evaluate
    y_pred = model.predict(X_test)
    y_pred_proba = model.predict_proba(X_test)[:, 1]
    
    print("\n" + "="*60)
    print("MODEL EVALUATION")
    print("="*60)
    print(classification_report(y_test, y_pred, target_names=['Success', 'Failure']))
    
    auc = roc_auc_score(y_test, y_pred_proba)
    print(f"\nROC AUC Score: {auc:.4f}")
    
    # Cross-validation
    cv_scores = cross_val_score(model, X, y, cv=5, scoring='roc_auc')
    print(f"Cross-validation AUC: {cv_scores.mean():.4f} (+/- {cv_scores.std():.4f})")
    
    # Feature importance (from base estimator)
    feature_importance = base_model.fit(X_train, y_train).feature_importances_
    importance_df = pd.DataFrame({
        'feature': feature_cols,
        'importance': feature_importance
    }).sort_values('importance', ascending=False)
    
    print("\nFeature Importance:")
    print(importance_df.to_string(index=False))
    
    # Save model and metadata
    output_path = Path(output_dir)
    output_path.mkdir(exist_ok=True)
    
    joblib.dump(model, output_path / 'risk_model.pkl')
    
    metadata = {
        'model_type': 'CalibratedGradientBoostingClassifier',
        'features': feature_cols,
        'training_samples': len(X_train),
        'test_auc': float(auc),
        'cv_auc_mean': float(cv_scores.mean()),
        'cv_auc_std': float(cv_scores.std()),
        'feature_importance': importance_df.to_dict('records'),
        'trained_at': pd.Timestamp.now().isoformat()
    }
    
    with open(output_path / 'model_metadata.json', 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print(f"\nModel saved to {output_path / 'risk_model.pkl'}")
    print(f"Metadata saved to {output_path / 'model_metadata.json'}")
    
    return model, metadata

if __name__ == '__main__':
    train_model()