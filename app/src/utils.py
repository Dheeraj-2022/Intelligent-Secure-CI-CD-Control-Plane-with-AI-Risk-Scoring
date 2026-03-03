"""
Utility functions for the sample application
"""
import hashlib
from typing import Dict, Any

def hash_data(data: str) -> str:
    """
    Create SHA256 hash of input data
    
    Args:
        data: Input string to hash
        
    Returns:
        Hexadecimal hash string
    """
    return hashlib.sha256(data.encode()).hexdigest()

def validate_payload(payload: Dict[str, Any]) -> bool:
    """
    Validate incoming payload structure
    
    Args:
        payload: Dictionary to validate
        
    Returns:
        True if valid, False otherwise
    """
    required_fields = ['id', 'data']
    return all(field in payload for field in required_fields)

def sanitize_input(user_input: str) -> str:
    """
    Sanitize user input to prevent injection attacks
    
    Args:
        user_input: Raw user input
        
    Returns:
        Sanitized string
    """
    # Remove potentially dangerous characters
    dangerous_chars = ['<', '>', '"', "'", '&', ';']
    sanitized = user_input
    for char in dangerous_chars:
        sanitized = sanitized.replace(char, '')
    return sanitized.strip()