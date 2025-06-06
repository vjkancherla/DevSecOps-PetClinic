#!/bin/bash

# K3D Development Environment Teardown Script
# Usage: ./k3d-teardown.sh [--keep-volume] [--keep-images]

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
VOLUME_NAME="${VOLUME_NAME:-k3d-data}"

# Default options
KEEP_VOLUME=false
KEEP_IMAGES=false

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

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep-volume)
                KEEP_VOLUME=true
                shift
                ;;
            --keep-images)
                KEEP_IMAGES=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    echo "K3D Development Environment Teardown Script"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --keep-volume    Don't delete the k3d-data Docker volume"
    echo "  --keep-images    Don't remove Docker images"
    echo "  -h, --help       Show this help message"
    echo
    echo "Examples:"
    echo "  $0                    # Full teardown"
    echo "  $0 --keep-volume     # Keep the data volume"
    echo "  $0 --keep-images     # Keep Docker images"
}

stop_docker_services() {
    log_info "Stopping Docker services"
    
    if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        if docker compose ps | grep -q "Up"; then
            docker compose stop
            log_success "Stopped Docker services"
        else
            log_warning "No running Docker services found"
        fi
        
        docker compose down
        log_success "Removed Docker containers and networks"
    else
        log_warning "No docker-compose file found, skipping Docker services cleanup"
    fi
}

delete_k3d_cluster() {
    log_info "Deleting k3d cluster: $CLUSTER_NAME"
    
    if k3d cluster list | grep -q $CLUSTER_NAME; then
        k3d cluster delete $CLUSTER_NAME
        log_success "Deleted k3d cluster: $CLUSTER_NAME"
    else
        log_warning "Cluster $CLUSTER_NAME not found"
    fi
}

remove_docker_volume() {
    if [ "$KEEP_VOLUME" = true ]; then
        log_info "Keeping Docker volume: $VOLUME_NAME (--keep-volume specified)"
        return
    fi
    
    log_info "Removing Docker volume: $VOLUME_NAME"
    
    if docker volume ls | grep -q $VOLUME_NAME; then
        docker volume rm $VOLUME_NAME
        log_success "Removed Docker volume: $VOLUME_NAME"
    else
        log_warning "Volume $VOLUME_NAME not found"
    fi
}

cleanup_kubeconfig() {
    log_info "Cleaning up kubeconfig files"
    
    if [ -f "k3d-kubeconfig" ]; then
        rm k3d-kubeconfig
        log_success "Removed k3d-kubeconfig file"
    else
        log_warning "k3d-kubeconfig file not found"
    fi
}

cleanup_docker_images() {
    if [ "$KEEP_IMAGES" = true ]; then
        log_info "Keeping Docker images (--keep-images specified)"
        return
    fi
    
    log_info "Cleaning up unused Docker images"
    
    # Remove dangling images
    if docker images -f "dangling=true" -q | wc -l | grep -q "0"; then
        log_warning "No dangling images to remove"
    else
        docker image prune -f
        log_success "Removed dangling Docker images"
    fi
    
    # Optional: Remove k3d specific images (commented out by default)
    # Uncomment the following lines if you want to remove k3d images as well
    # log_info "Removing k3d related images"
    # docker images | grep k3d | awk '{print $3}' | xargs -r docker rmi -f
}

cleanup_docker_networks() {
    log_info "Cleaning up unused Docker networks"
    
    # Remove unused networks
    docker network prune -f
    log_success "Cleaned up unused Docker networks"
}

verify_cleanup() {
    log_info "Verifying cleanup..."
    
    # Check if cluster is gone
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        log_error "Cluster $CLUSTER_NAME still exists"
        return 1
    fi
    
    # Check if volume is gone (if it should be)
    if [ "$KEEP_VOLUME" = false ] && docker volume ls | grep -q "$VOLUME_NAME"; then
        log_error "Volume $VOLUME_NAME still exists"
        return 1
    fi
    
    # Check if kubeconfig file is gone
    if [ -f "k3d-kubeconfig" ]; then
        log_error "k3d-kubeconfig file still exists"
        return 1
    fi
    
    log_success "Cleanup verification passed"
}

main() {
    parse_arguments "$@"
    
    log_info "Starting K3D Development Environment Teardown"
    
    if [ "$KEEP_VOLUME" = true ]; then
        log_info "Volume preservation: ENABLED"
    fi
    
    if [ "$KEEP_IMAGES" = true ]; then
        log_info "Image preservation: ENABLED"
    fi
    
    echo
    
    # Confirmation prompt
    log_warning "This will tear down your entire k3d development environment!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Teardown cancelled"
        exit 0
    fi
    
    echo
    
    stop_docker_services
    delete_k3d_cluster
    remove_docker_volume
    cleanup_kubeconfig
    cleanup_docker_images
    cleanup_docker_networks
    verify_cleanup
    
    echo
    log_success "Teardown completed successfully!"
    
    if [ "$KEEP_VOLUME" = true ]; then
        log_info "Note: Volume $VOLUME_NAME was preserved"
    fi
    
    if [ "$KEEP_IMAGES" = true ]; then
        log_info "Note: Docker images were preserved"
    fi
}

# Run main function with all arguments
main "$@"