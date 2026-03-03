"""
Generate synthetic training dataset for risk scoring model
"""
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random

np.random.seed(42)
random.seed(42)

def generate_synthetic_dataset(n_samples=1000):
    """
    Generate synthetic pipeline execution data
    
    Features:
    - changed_files: Number of files changed in commit
    - commit_message_length: Length of commit message
    - hour_of_day: Hour when build was triggered
    - day_of_week: Day of week (0=Monday)
    - code_coverage: Code coverage percentage
    - critical_vulns: Number of critical vulnerabilities
    - test_count: Number of tests
    - build_history_failures: Recent failure rate
    - file_types_changed: Diversity of file types
    - author_experience: Commits by author in last 30 days
    
    Target:
    - pipeline_failed: 1 if pipeline failed, 0 if succeeded
    """
    
    data = []
    
    for i in range(n_samples):
        # Generate features
        changed_files = np.random.poisson(8)
        commit_msg_len = np.random.normal(50, 20)
        hour = np.random.randint(0, 24)
        day_of_week = np.random.randint(0, 7)
        code_coverage = np.random.beta(8, 2) * 100  # Skewed toward high coverage
        critical_vulns = np.random.poisson(0.5)  # Rare critical vulns
        test_count = np.random.normal(50, 15)
        build_history_failures = np.random.beta(2, 8)  # Skewed toward low failure rate
        file_types_changed = np.random.poisson(3)
        author_experience = np.random.gamma(5, 10)
        
        # Generate target with realistic dependencies
        failure_probability = (
            0.05 +  # Base failure rate
            0.02 * (changed_files > 15) +  # Large changes increase risk
            0.03 * (commit_msg_len < 20) +  # Poor commit messages
            0.04 * (hour < 6 or hour > 22) +  # Off-hours builds
            0.15 * (code_coverage < 70) +  # Low coverage
            0.30 * (critical_vulns > 0) +  # Critical vulnerabilities
            0.05 * (test_count < 30) +  # Insufficient tests
            0.10 * (build_history_failures > 0.3) +  # Recent failures
            0.02 * (file_types_changed > 5) +  # Too many file types
            0.03 * (author_experience < 10)  # Inexperienced author
        )
        
        pipeline_failed = 1 if np.random.random() < failure_probability else 0
        
        data.append({
            'build_number': i + 1,
            'changed_files': int(max(1, changed_files)),
            'commit_message_length': int(max(10, commit_msg_len)),
            'hour_of_day': hour,
            'day_of_week': day_of_week,
            'code_coverage': round(min(100, max(0, code_coverage)), 2),
            'critical_vulns': int(critical_vulns),
            'test_count': int(max(10, test_count)),
            'build_history_failures': round(min(1, max(0, build_history_failures)), 3),
            'file_types_changed': int(max(1, file_types_changed)),
            'author_experience': int(max(1, author_experience)),
            'pipeline_failed': pipeline_failed
        })
    
    df = pd.DataFrame(data)
    
    # Add some realistic noise
    df.loc[df.sample(frac=0.05).index, 'pipeline_failed'] = 1 - df.loc[df.sample(frac=0.05).index, 'pipeline_failed']
    
    return df

if __name__ == '__main__':
    df = generate_synthetic_dataset(1000)
    df.to_csv('synthetic_dataset.csv', index=False)
    
    print("Dataset generated successfully!")
    print(f"Total samples: {len(df)}")
    print(f"Failure rate: {df['pipeline_failed'].mean():.2%}")
    print("\nFeature statistics:")
    print(df.describe())