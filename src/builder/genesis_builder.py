#!/usr/bin/env python3
"""
Genesis Builder - Container Building and Orchestration for Singularity Engine

This module implements the main Genesis Builder class that builds and deploys
Docker containers for the Singularity Engine ecosystem.
"""

import os
import sys
import uuid
import yaml
import logging
import datetime
import subprocess
from typing import Dict, List, Any, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('genesis_builder')

class GenesisBuilder:
    """
    Main builder class for Singularity Engine containers.
    
    Responsible for building and orchestrating Docker containers
    for all Singularity Engine components.
    """
    
    def __init__(self, config_path: str = None):
        """
        Initialize the Genesis Builder.
        
        Args:
            config_path: Path to configuration file
        """
        self.builder_id = str(uuid.uuid4())
        logger.info(f"Initializing Genesis Builder instance {self.builder_id}")
        
        # Load configuration
        self.config = self._load_config(config_path)
        
        # Initialize component definitions
        self.components = self._init_component_definitions()
        
        logger.info(f"Genesis Builder initialized with {len(self.components)} component definitions")
    
    def _load_config(self, config_path: Optional[str] = None) -> Dict[str, Any]:
        """
        Load configuration from file or use defaults.
        
        Args:
            config_path: Path to configuration file
            
        Returns:
            Dict containing configuration settings
        """
        if not config_path:
            config_path = os.environ.get('GENESIS_CONFIG', 'configs/builder_config.yml')
            
        try:
            logger.info(f"Loading configuration from {config_path}")
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)
            return config
        except Exception as e:
            logger.error(f"Failed to load configuration: {str(e)}")
            logger.info("Using default configuration")
            return self._default_config()
    
    def _default_config(self) -> Dict[str, Any]:
        """
        Create default configuration when no config file is found.
        
        Returns:
            Dict containing default configuration
        """
        return {
            'registry': {
                'url': os.environ.get('REGISTRY_URL', 'localhost:5000'),
                'username': os.environ.get('REGISTRY_USERNAME', ''),
                'password': os.environ.get('REGISTRY_PASSWORD', ''),
            },
            'kubernetes': {
                'namespace': 'singularity-system',
                'service_account': 'singularity-sa',
                'resource_limits': {
                    'cpu': '1',
                    'memory': '1Gi'
                }
            },
            'components': {
                'singularity-engine': {
                    'repository': 'singularity-engine',
                    'tag': 'latest',
                    'build_args': [],
                    'dockerfile': 'Dockerfile',
                    'context': '.'
                },
                'timescaledb': {
                    'repository': 'timescaledb',
                    'tag': 'latest-pg14',
                    'external': True
                }
            }
        }
    
    def _init_component_definitions(self) -> Dict[str, Any]:
        """
        Initialize component definitions from configuration.
        
        Returns:
            Dict containing component definitions
        """
        components = self.config.get('components', {})
        
        # Add default components if not in config
        default_components = {
            'singularity-engine': {
                'repository': 'singularity-engine',
                'tag': 'latest',
                'build_args': [],
                'dockerfile': 'Dockerfile',
                'context': '.'
            },
            'timescaledb': {
                'repository': 'timescaledb',
                'tag': 'latest-pg14',
                'external': True
            }
        }
        
        for name, definition in default_components.items():
            if name not in components:
                components[name] = definition
        
        return components
    
    def build_all_components(self) -> Dict[str, Any]:
        """
        Build all components defined in configuration.
        
        Returns:
            Dict containing build results for each component
        """
        logger.info(f"Building all components: {', '.join(self.components.keys())}")
        
        results = {}
        for name, definition in self.components.items():
            # Skip external components (pulled from public registry)
            if definition.get('external', False):
                logger.info(f"Skipping build for external component: {name}")
                results[name] = {'status': 'skipped', 'external': True}
                continue
            
            # Build component
            logger.info(f"Building component: {name}")
            result = self.build_component(name)
            results[name] = result
        
        return results
    
    def build_component(self, component_name: str) -> Dict[str, Any]:
        """
        Build a single component.
        
        Args:
            component_name: Name of the component to build
            
        Returns:
            Dict containing build result
        """
        if component_name not in self.components:
            logger.error(f"Component not found: {component_name}")
            return {'status': 'error', 'message': f"Component not found: {component_name}"}
        
        component = self.components[component_name]
        
        # Skip external components
        if component.get('external', False):
            logger.info(f"Skipping build for external component: {component_name}")
            return {'status': 'skipped', 'external': True}
        
        # Prepare build arguments
        repository = component.get('repository', component_name)
        tag = component.get('tag', 'latest')
        dockerfile = component.get('dockerfile', 'Dockerfile')
        context = component.get('context', '.')
        build_args = component.get('build_args', [])
        
        # Format tag with date for versioning
        date_tag = f"{tag}-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}"
        
        # Construct image name
        registry_url = self.config.get('registry', {}).get('url', 'localhost:5000')
        image_name = f"{registry_url}/{repository}"
        
        # Construct docker build command
        cmd = ['docker', 'build', '-t', f"{image_name}:{date_tag}", '-t', f"{image_name}:{tag}"]
        
        # Add build arguments
        for arg in build_args:
            cmd.extend(['--build-arg', arg])
        
        # Add Dockerfile and context
        cmd.extend(['-f', dockerfile, context])
        
        logger.info(f"Building image {image_name}:{date_tag}")
        logger.debug(f"Build command: {' '.join(cmd)}")
        
        try:
            # Execute build command
            process = subprocess.Popen(
                cmd, 
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE,
                universal_newlines=True
            )
            
            stdout, stderr = process.communicate()
            
            if process.returncode != 0:
                logger.error(f"Failed to build {component_name}: {stderr}")
                return {
                    'status': 'error',
                    'returncode': process.returncode,
                    'stdout': stdout,
                    'stderr': stderr
                }
            
            logger.info(f"Successfully built {component_name}")
            
            # Push image to registry
            push_result = self._push_image(f"{image_name}:{date_tag}")
            push_result_latest = self._push_image(f"{image_name}:{tag}")
            
            return {
                'status': 'success',
                'image': f"{image_name}:{date_tag}",
                'latest_image': f"{image_name}:{tag}",
                'build_time': datetime.datetime.now().isoformat(),
                'push_results': {
                    'versioned': push_result,
                    'latest': push_result_latest
                }
            }
        except Exception as e:
            logger.error(f"Error building {component_name}: {str(e)}")
            return {'status': 'error', 'message': str(e)}
    
    def _push_image(self, image_name: str) -> Dict[str, Any]:
        """
        Push an image to the registry.
        
        Args:
            image_name: Name of the image to push
            
        Returns:
            Dict containing push result
        """
        logger.info(f"Pushing image: {image_name}")
        
        try:
            # Login to registry if credentials provided
            registry = self.config.get('registry', {})
            if registry.get('username') and registry.get('password'):
                login_cmd = [
                    'docker', 'login',
                    registry.get('url', 'localhost:5000'),
                    '-u', registry.get('username'),
                    '-p', registry.get('password')
                ]
                
                login_process = subprocess.Popen(
                    login_cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    universal_newlines=True
                )
                login_stdout, login_stderr = login_process.communicate()
                
                if login_process.returncode != 0:
                    logger.error(f"Failed to login to registry: {login_stderr}")
                    return {'status': 'error', 'message': 'Registry login failed'}
            
            # Push image
            push_cmd = ['docker', 'push', image_name]
            
            push_process = subprocess.Popen(
                push_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True
            )
            push_stdout, push_stderr = push_process.communicate()
            
            if push_process.returncode != 0:
                logger.error(f"Failed to push image {image_name}: {push_stderr}")
                return {
                    'status': 'error',
                    'returncode': push_process.returncode,
                    'stdout': push_stdout,
                    'stderr': push_stderr
                }
            
            logger.info(f"Successfully pushed image {image_name}")
            return {'status': 'success', 'image': image_name}
        except Exception as e:
            logger.error(f"Error pushing image {image_name}: {str(e)}")
            return {'status': 'error', 'message': str(e)}
    
    def deploy_to_kubernetes(self, cloud_provider: str = 'vultr') -> Dict[str, Any]:
        """
        Deploy components to Kubernetes.
        
        Args:
            cloud_provider: Cloud provider to deploy to
            
        Returns:
            Dict containing deployment results
        """
        logger.info(f"Deploying to Kubernetes on {cloud_provider}")
        
        try:
            # Apply Kubernetes configuration
            kustomize_path = f"kubernetes/cloud-providers/{cloud_provider}/"
            
            # Check if kustomize path exists
            if not os.path.exists(kustomize_path):
                logger.error(f"Kustomize path not found: {kustomize_path}")
                return {'status': 'error', 'message': f"Kustomize path not found: {kustomize_path}"}
            
            # Run kubectl apply
            cmd = ['kubectl', 'apply', '-k', kustomize_path]
            
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True
            )
            stdout, stderr = process.communicate()
            
            if process.returncode != 0:
                logger.error(f"Failed to deploy to Kubernetes: {stderr}")
                return {
                    'status': 'error',
                    'returncode': process.returncode,
                    'stdout': stdout,
                    'stderr': stderr
                }
            
            logger.info(f"Successfully deployed to Kubernetes on {cloud_provider}")
            return {
                'status': 'success',
                'cloud_provider': cloud_provider,
                'deployment_time': datetime.datetime.now().isoformat(),
                'kubectl_output': stdout
            }
        except Exception as e:
            logger.error(f"Error deploying to Kubernetes: {str(e)}")
            return {'status': 'error', 'message': str(e)}
    
    def get_component_status(self, component_name: Optional[str] = None) -> Dict[str, Any]:
        """
        Get status of components.
        
        Args:
            component_name: Optional name of specific component to check
            
        Returns:
            Dict containing component status
        """
        if component_name and component_name not in self.components:
            logger.error(f"Component not found: {component_name}")
            return {'status': 'error', 'message': f"Component not found: {component_name}"}
        
        try:
            # Check Docker images
            components_to_check = [component_name] if component_name else self.components.keys()
            
            status = {}
            for name in components_to_check:
                component = self.components.get(name, {})
                
                # Skip status check for external components
                if component.get('external', False):
                    status[name] = {'status': 'external', 'message': 'External component'}
                    continue
                
                repository = component.get('repository', name)
                tag = component.get('tag', 'latest')
                registry_url = self.config.get('registry', {}).get('url', 'localhost:5000')
                image_name = f"{registry_url}/{repository}:{tag}"
                
                # Check if image exists
                cmd = ['docker', 'image', 'inspect', image_name]
                
                process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    universal_newlines=True
                )
                process.communicate()
                
                if process.returncode == 0:
                    status[name] = {'status': 'available', 'image': image_name}
                else:
                    status[name] = {'status': 'not_built', 'image': image_name}
            
            return status
        except Exception as e:
            logger.error(f"Error checking component status: {str(e)}")
            return {'status': 'error', 'message': str(e)}
    
    def get_kubernetes_status(self, namespace: Optional[str] = None) -> Dict[str, Any]:
        """
        Get status of Kubernetes deployments.
        
        Args:
            namespace: Optional namespace to check
            
        Returns:
            Dict containing Kubernetes deployment status
        """
        if not namespace:
            namespace = self.config.get('kubernetes', {}).get('namespace', 'singularity-system')
        
        try:
            # Check if namespace exists
            ns_cmd = ['kubectl', 'get', 'namespace', namespace]
            
            ns_process = subprocess.Popen(
                ns_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True
            )
            ns_process.communicate()
            
            if ns_process.returncode != 0:
                logger.error(f"Namespace not found: {namespace}")
                return {'status': 'error', 'message': f"Namespace not found: {namespace}"}
            
            # Get deployments
            deploy_cmd = ['kubectl', 'get', 'deployments', '-n', namespace, '-o', 'json']
            
            deploy_process = subprocess.Popen(
                deploy_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True
            )
            deploy_stdout, deploy_stderr = deploy_process.communicate()
            
            if deploy_process.returncode != 0:
                logger.error(f"Failed to get deployments: {deploy_stderr}")
                return {
                    'status': 'error',
                    'returncode': deploy_process.returncode,
                    'stderr': deploy_stderr
                }
            
            # Get services
            svc_cmd = ['kubectl', 'get', 'services', '-n', namespace, '-o', 'json']
            
            svc_process = subprocess.Popen(
                svc_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True
            )
            svc_stdout, svc_stderr = svc_process.communicate()
            
            if svc_process.returncode != 0:
                logger.error(f"Failed to get services: {svc_stderr}")
                return {
                    'status': 'error',
                    'returncode': svc_process.returncode,
                    'stderr': svc_stderr
                }
            
            # Return raw output for now, would parse JSON in production
            return {
                'status': 'success',
                'namespace': namespace,
                'deployments': deploy_stdout,
                'services': svc_stdout
            }
        except Exception as e:
            logger.error(f"Error checking Kubernetes status: {str(e)}")
            return {'status': 'error', 'message': str(e)}


# Example usage when run directly
if __name__ == "__main__":
    logger.info("Starting Genesis Builder as standalone module")
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
    else:
        command = "status"
    
    builder = GenesisBuilder()
    
    if command == "build":
        # Build all components
        logger.info("Building all components")
        results = builder.build_all_components()
        print(yaml.dump(results, default_flow_style=False))
    elif command == "deploy":
        # Deploy to Kubernetes
        cloud_provider = sys.argv[2] if len(sys.argv) > 2 else "vultr"
        logger.info(f"Deploying to Kubernetes on {cloud_provider}")
        results = builder.deploy_to_kubernetes(cloud_provider)
        print(yaml.dump(results, default_flow_style=False))
    else:
        # Show status
        logger.info("Checking component status")
        status = builder.get_component_status()
        k8s_status = builder.get_kubernetes_status()
        
        print("=== Component Status ===")
        print(yaml.dump(status, default_flow_style=False))
        
        print("\n=== Kubernetes Status ===")
        print(yaml.dump(k8s_status, default_flow_style=False))