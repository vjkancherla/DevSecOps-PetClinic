#!/bin/bash

# K3D Development Environment Setup Script
# Usage: ./k3d-setup.sh [jenkins-only]

set -e  # Exit on any error

# Load environment variables safely
set -a  # Automatically export all variables
source .env.credentials >/dev/null 2>&1 || true
set +a

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Load from environment variables
CLUSTER_NAME="${CLUSTER_NAME:-mycluster}"
NAMESPACE="${NAMESPACE:-jenkins}"
VOLUME_NAME="${VOLUME_NAME:-k3d-data}"
K3D_SUBNET="${K3D_SUBNET:-172.19.0.0/16}"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if required tools are installed
    for tool in docker k3d kubectl; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running"
        exit 1
    fi
    
    # Check if credentials are set
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ] || [ -z "$DOCKER_EMAIL" ]; then
        log_error "Docker credentials not set in environment variables"
        log_error "Please source the .env.credentials file: source .env.credentials"
        log_error "Required variables: DOCKER_USERNAME, DOCKER_PASSWORD, DOCKER_EMAIL"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

create_docker_volume() {
    log_info "Creating Docker volume: $VOLUME_NAME"
    
    if docker volume ls | grep -q "$VOLUME_NAME"; then
        log_warning "Volume $VOLUME_NAME already exists, skipping creation"
    else
        docker volume create $VOLUME_NAME
        log_success "Created Docker volume: $VOLUME_NAME"
    fi
}

start_k3d_cluster() {
    log_info "Starting k3d cluster: $CLUSTER_NAME"
    
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        log_warning "Cluster $CLUSTER_NAME already exists"
        log_info "Stopping existing cluster..."
        k3d cluster stop $CLUSTER_NAME
        log_info "Deleting existing cluster..."
        k3d cluster delete $CLUSTER_NAME
    fi
    
    log_info "Creating new k3d cluster..."
    k3d cluster create $CLUSTER_NAME \
        --servers 1 \
        --agents 1 \
        --subnet $K3D_SUBNET \
        --volume $VOLUME_NAME:/mnt/data@agent:0
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    log_success "K3d cluster $CLUSTER_NAME is ready"
}

create_namespace() {
    log_info "Creating namespace: $NAMESPACE"
    
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        log_warning "Namespace $NAMESPACE already exists, skipping creation"
    else
        kubectl create namespace $NAMESPACE
        log_success "Created namespace: $NAMESPACE"
    fi
}

apply_persistence_store() {
    log_info "Applying persistence store configuration"
    
    if [ ! -f "k3d-persistence-store.yaml" ]; then
        log_error "k3d-persistence-store.yaml not found in current directory"
        exit 1
    fi
    
    kubectl apply -f k3d-persistence-store.yaml
    log_success "Applied persistence store configuration"
}

create_docker_secret() {
    log_info "Creating Docker registry secret"
    
    # Delete existing secret if it exists
    if kubectl get secret docker-credentials -n $NAMESPACE &> /dev/null; then
        log_warning "Secret docker-credentials already exists, deleting and recreating"
        kubectl delete secret docker-credentials -n $NAMESPACE
    fi
    
    kubectl create secret docker-registry docker-credentials \
        -n $NAMESPACE \
        --docker-server=https://index.docker.io/v1/ \
        --docker-username=$DOCKER_USERNAME \
        --docker-password=$DOCKER_PASSWORD \
        --docker-email=$DOCKER_EMAIL
    
    log_success "Created Docker registry secret"
}

prepare_kubeconfig() {
    log_info "Preparing k3d kubeconfig"
    
    # Get K3D server IP
    K3D_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' k3d-$CLUSTER_NAME-server-0)
    
    if [ -z "$K3D_IP" ]; then
        log_error "Failed to get K3D server IP"
        exit 1
    fi
    
    log_info "K3d Server IP: $K3D_IP"
    
    # Prepare kubeconfig for Jenkins
    if [ ! -f ~/.kube/config ]; then
        log_error "~/.kube/config not found"
        exit 1
    fi
    
    cp ~/.kube/config k3d-kubeconfig
    
    # Use different sed syntax based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|server: .*|server: https://${K3D_IP}:6443|g" k3d-kubeconfig
    else
        # Linux
        sed -i "s|server: .*|server: https://${K3D_IP}:6443|g" k3d-kubeconfig
    fi
    
    log_success "Prepared k3d-kubeconfig file"
}

start_docker_services() {
    local services_to_start="$1"
    
    log_info "Starting Docker services via docker-compose"
    
    if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.yaml" ]; then
        log_error "docker-compose.yml or docker-compose.yaml not found in current directory"
        exit 1
    fi
    
    if [ "$services_to_start" = "jenkins-only" ]; then
        log_info "Starting Jenkins service only"
        docker compose up -d jenkins
        log_success "Started Jenkins service"
    else
        log_info "Starting all services (Jenkins and SonarQube)"
        docker compose up -d
        log_success "Started all Docker services"
    fi
}

update_jenkins_credentials() {
    log_info "Jenkins credential update reminder"
    log_warning "MANUAL STEP REQUIRED:"
    log_warning "1. Access Jenkins web interface"
    log_warning "2. Go to Manage Jenkins -> Credentials"
    log_warning "3. Update the 'k3d-kubeconfig' global credential"
    log_warning "4. Upload the new 'k3d-kubeconfig' file from the current directory"
}

main() {
    local services_mode="all"
    
    # Parse command line arguments
    if [ "$1" = "jenkins-only" ]; then
        services_mode="jenkins-only"
    fi
    
    log_info "Starting K3D Development Environment Setup"
    log_info "Services mode: $services_mode"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Namespace: $NAMESPACE"
    log_info "Volume: $VOLUME_NAME"
    log_info "Docker User: $DOCKER_USERNAME"
    echo
    
    check_prerequisites
    create_docker_volume
    start_k3d_cluster
    create_namespace
    apply_persistence_store
    create_docker_secret
    prepare_kubeconfig
    start_docker_services "$services_mode"
    update_jenkins_credentials
    
    echo
    log_success "Setup completed successfully!"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Namespace: $NAMESPACE"
    log_info "Kubeconfig: ./k3d-kubeconfig"
    
    if [ "$services_mode" = "jenkins-only" ]; then
        log_info "Services: Jenkins only"
    else
        log_info "Services: Jenkins and SonarQube"
    fi
}

# Run main function with all arguments
main "$@"