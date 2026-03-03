"""
Unit tests for main application
"""
import unittest
import json
from src.main import app

class TestMainApp(unittest.TestCase):
    
    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True
    
    def test_health_endpoint(self):
        """Test health check returns 200"""
        response = self.app.get('/health')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'healthy')
    
    def test_ready_endpoint(self):
        """Test readiness probe"""
        response = self.app.get('/ready')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'ready')
    
    def test_root_endpoint(self):
        """Test root endpoint returns service info"""
        response = self.app.get('/')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn('service', data)
        self.assertEqual(data['service'], 'sample-app')
    
    def test_process_endpoint(self):
        """Test process endpoint"""
        response = self.app.post('/api/v1/process', 
                                 json={'data': 'test'},
                                 content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn('message', data)
    
    def test_metrics_endpoint(self):
        """Test Prometheus metrics endpoint"""
        response = self.app.get('/metrics')
        self.assertEqual(response.status_code, 200)

if __name__ == '__main__':
    unittest.main()