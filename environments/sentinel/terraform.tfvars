# ─────────────────────────────────────────────────────────────────────────────
# All environment-specific values live here.
# To spin up a new environment, copy this file, change these values, and point
# the GitHub Actions backend-config at a different S3 key.
# ─────────────────────────────────────────────────────────────────────────────

# AWS
region = "us-east-2"

# Kubernetes
kubernetes_version = "1.31"

# Networking
gateway_vpc_cidr = "10.0.0.0/16"
backend_vpc_cidr = "10.1.0.0/16"

# Compute (cost-optimised for POC; bump to t3.large + desired_size=2 for staging)
node_instance_types = ["t3.medium"]
node_desired_size   = 1

# IAM — the bootstrap workflow creates this role; deploy.yml assumes it via OIDC
gha_role_name = "sentinel-gha-ci3"

# Tags applied to every resource
tags = {
  Project     = "rapyd-sentinel"
  Environment = "poc"
  ManagedBy   = "terraform"
}
