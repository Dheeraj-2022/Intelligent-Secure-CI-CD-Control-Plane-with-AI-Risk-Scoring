"""
Sample microservice with health endpoints and metrics
"""
from flask import Flask, jsonify
from prometheus_client import Counter, Histogram, generate_latest
import time
import logging

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
REQUEST_COUNT = Counter('app_requests_total', 'Total requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('app_request_duration_seconds', 'Request latency', ['endpoint'])

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "timestamp": time.time()}), 200

@app.route('/ready')
def ready():
    """Readiness probe"""
    # Add actual readiness checks (DB, dependencies, etc.)
    return jsonify({"status": "ready"}), 200

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

@app.route('/api/v1/process', methods=['POST'])
def process():
    """Sample business logic endpoint"""
    start_time = time.time()
    try:
        # Simulate processing
        result = {"message": "Processing complete", "version": "1.0.0"}
        REQUEST_COUNT.labels(method='POST', endpoint='/api/v1/process', status=200).inc()
        return jsonify(result), 200
    finally:
        REQUEST_LATENCY.labels(endpoint='/api/v1/process').observe(time.time() - start_time)

@app.route('/')
def root():
    """Root endpoint"""
    return jsonify({
        "service": "sample-app",
        "version": "1.0.0",
        "endpoints": ["/health", "/ready", "/metrics", "/api/v1/process"]
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)