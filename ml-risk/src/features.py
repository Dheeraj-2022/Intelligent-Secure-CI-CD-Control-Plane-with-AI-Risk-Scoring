"""
Feature extraction for risk scoring
"""
import re
from datetime import datetime
from typing import Dict, Any

def extract_features(build_context: Dict[str, Any]) -> Dict[str, float]:
    """
    Extract features from build context
    
    Args:
        build_context: Dictionary containing build metadata
        
    Returns:
        Dictionary of extracted features
    """
    features = {}
    
    # File change metrics
    features['changed_files'] = int(build_context.get('changed_files', 5))
    
    # Commit message quality
    commit_msg = build_context.get('commit_message', '')
    features['commit_message_length'] = len(commit_msg)
    features['has_ticket_reference'] = 1 if re.search(r'(JIRA|TICKET|#\d+)', commit_msg, re.I) else 0
    
    # Temporal features
    now = datetime.now()
    features['hour_of_day'] = now.hour
    features['day_of_week'] = now.weekday()
    features['is_weekend'] = 1 if now.weekday() >= 5 else 0
    
    # Code quality metrics
    features['code_coverage'] = float(build_context.get('coverage', 0))
    features['critical_vulns'] = int(build_context.get('critical_vulns', 0))
    features['test_count'] = int(build_context.get('test_count', 50))
    
    # Historical metrics (would come from database in production)
    features['build_history_failures'] = float(build_context.get('recent_failure_rate', 0.1))
    
    # File diversity
    changed_files_list = build_context.get('changed_files_list', [])
    file_extensions = set(f.split('.')[-1] for f in changed_files_list if '.' in f)
    features['file_types_changed'] = len(file_extensions)
    
    # Author experience (mock - would query git history)
    features['author_experience'] = int(build_context.get('author_commits_30d', 20))
    
    return features

def get_feature_names():
    """Return list of feature names in expected order"""
    return [
        'changed_files',
        'commit_message_length',
        'hour_of_day',
        'day_of_week',
        'code_coverage',
        'critical_vulns',
        'test_count',
        'build_history_failures',
        'file_types_changed',
        'author_experience'
    ]