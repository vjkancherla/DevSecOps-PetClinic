# 1. Create your credentials file from template
cp .env.credentials.template .env.credentials

# 2. Edit with your actual credentials
nano .env.credentials  # or your preferred editor

# 3. Load credentials into your shell
source .env.credentials

# 4. Verify credentials are loaded
make check-env