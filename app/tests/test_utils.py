"""
Unit tests for utility functions
"""
import unittest
from src.utils import hash_data, validate_payload, sanitize_input

class TestUtils(unittest.TestCase):
    
    def test_hash_data(self):
        """Test data hashing"""
        data = "test_string"
        hashed = hash_data(data)
        self.assertEqual(len(hashed), 64)  # SHA256 produces 64 hex chars
        # Same input should produce same hash
        self.assertEqual(hash_data(data), hashed)
    
    def test_validate_payload_valid(self):
        """Test payload validation with valid data"""
        payload = {'id': '123', 'data': 'test'}
        self.assertTrue(validate_payload(payload))
    
    def test_validate_payload_invalid(self):
        """Test payload validation with invalid data"""
        payload = {'id': '123'}  # Missing 'data' field
        self.assertFalse(validate_payload(payload))
    
    def test_sanitize_input(self):
        """Test input sanitization"""
        malicious = "<script>alert('xss')</script>"
        sanitized = sanitize_input(malicious)
        self.assertNotIn('<', sanitized)
        self.assertNotIn('>', sanitized)
        
    def test_sanitize_input_clean(self):
        """Test sanitization doesn't affect clean input"""
        clean = "normal text 123"
        sanitized = sanitize_input(clean)
        self.assertEqual(clean, sanitized)

if __name__ == '__main__':
    unittest.main()