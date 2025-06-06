# Load credentials (once per shell session)
source .env.credentials

# Run setup
make setup
# OR
./k3d-setup.sh

# Later... teardown
make teardown
# OR  
./k3d-teardown.sh

# Additonal Make commands
make setup              # Full setup
make setup-jenkins      # Jenkins only
make kubeconfig         # Generate/update k3d-kubeconfig file
make teardown           # Complete teardown
make status             # Check current status