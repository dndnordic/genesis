#!/usr/bin/env python3
"""
Genesis API - Integration Interface for Singularity Engine

This module provides API endpoints for integration between Genesis Builder and
Singularity Engine, allowing build and deployment requests and status reporting.
"""

import os
import sys
import json
import uuid
import logging
import datetime
import threading
import http.server
import socketserver
from typing import Dict, List, Any, Optional
from urllib.parse import urlparse, parse_qs

# Import Genesis Builder
from genesis_builder import GenesisBuilder

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('genesis_api')

# Global instance of Genesis Builder
genesis_builder = GenesisBuilder()
# Lock for thread safety during operations
builder_lock = threading.Lock()
# Store ongoing operations
operations = {}


class GenesisAPIHandler(http.server.BaseHTTPRequestHandler):
    """
    HTTP request handler for Genesis API.
    
    Provides endpoints for build and deploy operations.
    """
    
    def do_GET(self):
        """Handle GET requests for status checks."""
        try:
            parsed_url = urlparse(self.path)
            path = parsed_url.path
            
            # Status endpoint
            if path == '/api/status':
                self._handle_status()
            # Operation status endpoint
            elif path.startswith('/api/operations/'):
                operation_id = path.split('/')[-1]
                self._handle_operation_status(operation_id)
            # Component status endpoint
            elif path == '/api/components':
                self._handle_component_status()
            # Kubernetes status endpoint
            elif path == '/api/kubernetes':
                self._handle_kubernetes_status()
            # Unknown endpoint
            else:
                self._send_error(404, "Not Found")
        except Exception as e:
            logger.error(f"Error handling GET request: {str(e)}")
            self._send_error(500, f"Internal Server Error: {str(e)}")
    
    def do_POST(self):
        """Handle POST requests for operations."""
        try:
            parsed_url = urlparse(self.path)
            path = parsed_url.path
            
            # Get content length
            content_length = int(self.headers['Content-Length'])
            # Read request body
            request_body = self.rfile.read(content_length).decode('utf-8')
            request_data = json.loads(request_body) if request_body else {}
            
            # Build endpoint
            if path == '/api/build':
                self._handle_build(request_data)
            # Deploy endpoint
            elif path == '/api/deploy':
                self._handle_deploy(request_data)
            # Build and deploy endpoint
            elif path == '/api/build-and-deploy':
                self._handle_build_and_deploy(request_data)
            # Unknown endpoint
            else:
                self._send_error(404, "Not Found")
        except json.JSONDecodeError:
            self._send_error(400, "Invalid JSON in request body")
        except Exception as e:
            logger.error(f"Error handling POST request: {str(e)}")
            self._send_error(500, f"Internal Server Error: {str(e)}")
    
    def _handle_status(self):
        """Handle status request."""
        status = {
            'status': 'running',
            'version': '0.1.0',
            'timestamp': datetime.datetime.now().isoformat(),
            'operations': len(operations)
        }
        self._send_json_response(200, status)
    
    def _handle_operation_status(self, operation_id: str):
        """
        Handle operation status request.
        
        Args:
            operation_id: ID of operation to check
        """
        if operation_id in operations:
            self._send_json_response(200, operations[operation_id])
        else:
            self._send_error(404, f"Operation {operation_id} not found")
    
    def _handle_component_status(self):
        """Handle component status request."""
        with builder_lock:
            status = genesis_builder.get_component_status()
        self._send_json_response(200, status)
    
    def _handle_kubernetes_status(self):
        """Handle Kubernetes status request."""
        query = parse_qs(urlparse(self.path).query)
        namespace = query.get('namespace', [None])[0]
        
        with builder_lock:
            status = genesis_builder.get_kubernetes_status(namespace)
        self._send_json_response(200, status)
    
    def _handle_build(self, request_data: Dict[str, Any]):
        """
        Handle build request.
        
        Args:
            request_data: Request data containing component to build
        """
        # Check if component specified
        if 'component' not in request_data:
            self._send_error(400, "Missing required field: component")
            return
        
        component_name = request_data['component']
        operation_id = str(uuid.uuid4())
        
        # Create operation entry
        operations[operation_id] = {
            'id': operation_id,
            'type': 'build',
            'component': component_name,
            'status': 'pending',
            'timestamp': datetime.datetime.now().isoformat()
        }
        
        # Start build in background thread
        thread = threading.Thread(
            target=self._run_build,
            args=(operation_id, component_name)
        )
        thread.daemon = True
        thread.start()
        
        # Return operation ID
        self._send_json_response(
            202,
            {
                'operation_id': operation_id,
                'status': 'pending',
                'message': f'Building component {component_name}'
            }
        )
    
    def _run_build(self, operation_id: str, component_name: str):
        """
        Run build operation in background.
        
        Args:
            operation_id: ID of operation
            component_name: Name of component to build
        """
        try:
            operations[operation_id]['status'] = 'running'
            
            # Build component
            with builder_lock:
                result = genesis_builder.build_component(component_name)
            
            # Update operation with result
            operations[operation_id]['status'] = 'completed' if result.get('status') == 'success' else 'failed'
            operations[operation_id]['result'] = result
            operations[operation_id]['completed_at'] = datetime.datetime.now().isoformat()
        except Exception as e:
            logger.error(f"Error in build operation {operation_id}: {str(e)}")
            operations[operation_id]['status'] = 'failed'
            operations[operation_id]['error'] = str(e)
            operations[operation_id]['completed_at'] = datetime.datetime.now().isoformat()
    
    def _handle_deploy(self, request_data: Dict[str, Any]):
        """
        Handle deploy request.
        
        Args:
            request_data: Request data containing cloud provider
        """
        # Get cloud provider with default
        cloud_provider = request_data.get('cloud_provider', 'vultr')
        operation_id = str(uuid.uuid4())
        
        # Create operation entry
        operations[operation_id] = {
            'id': operation_id,
            'type': 'deploy',
            'cloud_provider': cloud_provider,
            'status': 'pending',
            'timestamp': datetime.datetime.now().isoformat()
        }
        
        # Start deploy in background thread
        thread = threading.Thread(
            target=self._run_deploy,
            args=(operation_id, cloud_provider)
        )
        thread.daemon = True
        thread.start()
        
        # Return operation ID
        self._send_json_response(
            202,
            {
                'operation_id': operation_id,
                'status': 'pending',
                'message': f'Deploying to {cloud_provider}'
            }
        )
    
    def _run_deploy(self, operation_id: str, cloud_provider: str):
        """
        Run deploy operation in background.
        
        Args:
            operation_id: ID of operation
            cloud_provider: Cloud provider to deploy to
        """
        try:
            operations[operation_id]['status'] = 'running'
            
            # Deploy to Kubernetes
            with builder_lock:
                result = genesis_builder.deploy_to_kubernetes(cloud_provider)
            
            # Update operation with result
            operations[operation_id]['status'] = 'completed' if result.get('status') == 'success' else 'failed'
            operations[operation_id]['result'] = result
            operations[operation_id]['completed_at'] = datetime.datetime.now().isoformat()
        except Exception as e:
            logger.error(f"Error in deploy operation {operation_id}: {str(e)}")
            operations[operation_id]['status'] = 'failed'
            operations[operation_id]['error'] = str(e)
            operations[operation_id]['completed_at'] = datetime.datetime.now().isoformat()
    
    def _handle_build_and_deploy(self, request_data: Dict[str, Any]):
        """
        Handle build and deploy request.
        
        Args:
            request_data: Request data containing components and cloud provider
        """
        # Check if components specified
        if 'components' not in request_data:
            self._send_error(400, "Missing required field: components")
            return
        
        components = request_data['components']
        cloud_provider = request_data.get('cloud_provider', 'vultr')
        operation_id = str(uuid.uuid4())
        
        # Create operation entry
        operations[operation_id] = {
            'id': operation_id,
            'type': 'build_and_deploy',
            'components': components,
            'cloud_provider': cloud_provider,
            'status': 'pending',
            'timestamp': datetime.datetime.now().isoformat()
        }
        
        # Start build and deploy in background thread
        thread = threading.Thread(
            target=self._run_build_and_deploy,
            args=(operation_id, components, cloud_provider)
        )
        thread.daemon = True
        thread.start()
        
        # Return operation ID
        self._send_json_response(
            202,
            {
                'operation_id': operation_id,
                'status': 'pending',
                'message': f'Building {len(components)} components and deploying to {cloud_provider}'
            }
        )
    
    def _run_build_and_deploy(self, operation_id: str, components: List[str], cloud_provider: str):
        """
        Run build and deploy operation in background.
        
        Args:
            operation_id: ID of operation
            components: List of components to build
            cloud_provider: Cloud provider to deploy to
        """
        try:
            operations[operation_id]['status'] = 'running'
            operations[operation_id]['build_results'] = {}
            
            # Build each component
            for component in components:
                operations[operation_id]['current_component'] = component
                
                # Build component
                with builder_lock:
                    result = genesis_builder.build_component(component)
                
                operations[operation_id]['build_results'][component] = result
                
                # If build failed, abort
                if result.get('status') != 'success':
                    operations[operation_id]['status'] = 'failed'
                    operations[operation_id]['error'] = f"Failed to build component {component}"
                    operations[operation_id]['completed_at'] = datetime.datetime.now().isoformat()
                    return
            
            # Deploy to Kubernetes
            operations[operation_id]['current_action'] = 'deploying'
            
            with builder_lock:
                deploy_result = genesis_builder.deploy_to_kubernetes(cloud_provider)
            
            operations[operation_id]['deploy_result'] = deploy_result
            
            # Update operation status
            operations[operation_id]['status'] = 'completed' if deploy_result.get('status') == 'success' else 'failed'
            if deploy_result.get('status') != 'success':
                operations[operation_id]['error'] = f"Failed to deploy to {cloud_provider}"
            
            operations[operation_id]['completed_at'] = datetime.datetime.now().isoformat()
        except Exception as e:
            logger.error(f"Error in build and deploy operation {operation_id}: {str(e)}")
            operations[operation_id]['status'] = 'failed'
            operations[operation_id]['error'] = str(e)
            operations[operation_id]['completed_at'] = datetime.datetime.now().isoformat()
    
    def _send_json_response(self, status_code: int, data: Any):
        """
        Send JSON response.
        
        Args:
            status_code: HTTP status code
            data: Data to send as JSON
        """
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))
    
    def _send_error(self, status_code: int, message: str):
        """
        Send error response.
        
        Args:
            status_code: HTTP status code
            message: Error message
        """
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            'error': message
        }).encode('utf-8'))


def start_api_server(port: int = 8080):
    """
    Start API server.
    
    Args:
        port: Port to listen on
    """
    try:
        # Create server
        server = socketserver.ThreadingTCPServer(('0.0.0.0', port), GenesisAPIHandler)
        logger.info(f"Genesis API server starting on port {port}")
        
        # Start server
        server.serve_forever()
    except Exception as e:
        logger.error(f"Error starting API server: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    port = int(os.environ.get('GENESIS_API_PORT', 8080))
    start_api_server(port)