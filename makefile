# K3D Development Environment Automation
# Usage: make <target>

include .env.credentials

# Set defaults if variables not defined
CLUSTER_NAME ?= mycluster
NAMESPACE ?= jenkins
VOLUME_NAME ?= k3d-data

.PHONY: help setup setup-jenkins teardown teardown-keep-volume teardown-keep-all status clean check-env kubeconfig

# Default target
help:
	@echo "K3D Development Environment Automation"
	@echo ""
	@echo "Available targets:"
	@echo "  setup              - Full setup (Jenkins + SonarQube)"
	@echo "  setup-jenkins      - Setup with Jenkins only"
	@echo "  teardown           - Complete teardown"
	@echo "  teardown-keep-vol  - Teardown but keep data volume"
	@echo "  teardown-keep-all  - Teardown but keep volume and images"
	@echo "  kubeconfig         - Generate/update k3d-kubeconfig file"
	@echo "  status             - Show current status"
	@echo "  clean              - Remove generated files"
	@echo "  check-env          - Check if credentials are loaded"
	@echo "  help               - Show this help"
	@echo ""
	@echo "IMPORTANT: Load credentials first:"
	@echo "  source .env.credentials"

check-env:
	@if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ] || [ -z "$DOCKER_EMAIL" ]; then \
		echo "❌ Credentials not loaded!"; \
		echo "Please run: source .env.credentials"; \
		echo ""; \
		echo "If .env.credentials doesn't exist:"; \
		echo "1. cp .env.credentials.template .env.credentials"; \
		echo "2. Edit .env.credentials with your values"; \
		echo "3. source .env.credentials"; \
		exit 1; \
	else \
		echo "✅ Credentials loaded successfully"; \
		echo "Docker User: $DOCKER_USERNAME"; \
		echo "Cluster: ${CLUSTER_NAME:-mycluster}"; \
		echo "Namespace: ${NAMESPACE:-jenkins}"; \
	fi

# Setup targets
setup: check-env
	@chmod +x k3d-setup.sh
	./k3d-setup.sh

setup-jenkins: check-env
	@chmod +x k3d-setup.sh
	./k3d-setup.sh jenkins-only

# Teardown targets
teardown:
	@chmod +x k3d-teardown.sh
	./k3d-teardown.sh

teardown-keep-vol:
	@chmod +x k3d-teardown.sh
	./k3d-teardown.sh --keep-volume

teardown-keep-all:
	@chmod +x k3d-teardown.sh
	./k3d-teardown.sh --keep-volume --keep-images

# Kubeconfig generation
kubeconfig:
	@echo "Generating k3d kubeconfig..."
	@if ! k3d cluster list | grep -q "$(CLUSTER_NAME)"; then \
		echo "❌ Error: Cluster $(CLUSTER_NAME) not found"; \
		echo "Available clusters:"; \
		k3d cluster list; \
		exit 1; \
	fi; \
	K3D_IP=$$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' k3d-$(CLUSTER_NAME)-server-0); \
	if [ -z "$$K3D_IP" ]; then \
		echo "❌ Error: Failed to get K3D server IP"; \
		echo "Tried to inspect: k3d-$(CLUSTER_NAME)-server-0"; \
		echo "Running containers:"; \
		docker ps --format '{{.Names}}'; \
		exit 1; \
	fi; \
	echo "K3d Server IP: $$K3D_IP"; \
	if [ ! -f ~/.kube/config ]; then \
		echo "❌ Error: ~/.kube/config not found"; \
		exit 1; \
	fi; \
	cp ~/.kube/config k3d-kubeconfig; \
	if [[ "$(shell uname)" == "Darwin" ]]; then \
		sed -i '' "s|server: .*|server: https://$$K3D_IP:6443|g" k3d-kubeconfig; \
	else \
		sed -i "s|server: .*|server: https://$$K3D_IP:6443|g" k3d-kubeconfig; \
	fi; \
	echo "✅ Generated k3d-kubeconfig successfully"; \
	echo "📁 File location: ./k3d-kubeconfig"; \
	echo "💡 Remember to update Jenkins credentials with this file"

# Status and utility targets
status:
	@echo "=== K3D Clusters ==="
	@k3d cluster list || echo "No k3d clusters found"
	@echo ""
	@echo "=== Docker Volumes ==="
	@docker volume ls | grep k3d-data || echo "No k3d-data volume found"
	@echo ""
	@echo "=== Docker Services ==="
	@if [ -f docker-compose.yml ] || [ -f docker-compose.yaml ]; then \
		docker compose ps; \
	else \
		echo "No docker-compose file found"; \
	fi
	@echo ""
	@echo "=== Kubernetes Context ==="
	@kubectl config current-context || echo "No kubernetes context set"

clean:
	@echo "Cleaning up generated files..."
	@rm -f k3d-kubeconfig
	@echo "✅ Removed k3d-kubeconfig"
	@echo "Done"