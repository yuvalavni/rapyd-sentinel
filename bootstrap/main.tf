data "aws_caller_identity" "current" {}

locals {
  bucket_name = "sentinel-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  tags = merge(var.tags, {
    Name = local.bucket_name
  })
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# GitHub OIDC is account-global. The challenge IAM user cannot
# iam:CreateOpenIDConnectProvider — look up the provider Rapyd already installed.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

module "gha" {
  source = "../modules/iam"

  create_eks_roles           = false
  create_github_oidc         = true
  create_oidc_provider       = false
  existing_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
  gha_role_name              = "sentinel-gha"
  github_org                 = var.github_org
  github_repo                = var.github_repo
  oidc_sub_refs = [
    "ref:refs/heads/main",
    "environment:aws",
    "environment:bootstrap",
  ]
  state_bucket_arn = aws_s3_bucket.state.arn
  tags             = var.tags
}

# Cannot UpdateAssumeRolePolicy on sentinel-gha. Create a sibling role with a
# repo-wide OIDC sub that matches GitHub-hosted runners.
module "gha_ci" {
  source = "../modules/iam"

  create_eks_roles           = false
  create_github_oidc         = true
  create_oidc_provider       = false
  existing_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
  gha_role_name              = "sentinel-gha-ci"
  github_org                 = var.github_org
  github_repo                = var.github_repo
  oidc_sub_refs              = ["*"]
  state_bucket_arn           = aws_s3_bucket.state.arn
  tags                       = var.tags
}

# sentinel-gha-ci was created before GitHub changed its OIDC sub format to include
# numeric IDs (owner@id/repo@id). iam:UpdateAssumeRolePolicy is denied, so we create
# a new role provisioned with BOTH old and new sub patterns from the start.
# New format discovered from OIDC token diagnostic:
#   repo:yuvalavni@15526311/rapyd-sentinel@1374424092:<ref>
# sentinel-gha-ci2 was already created with the wrong trust policy and iam:DeleteRole
# is also denied, so we use sentinel-gha-ci3 as the definitive role.
module "gha_ci2" {
  source = "../modules/iam"

  create_eks_roles           = false
  create_github_oidc         = true
  create_oidc_provider       = false
  existing_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
  gha_role_name              = "sentinel-gha-ci2"
  github_org                 = var.github_org
  github_repo                = var.github_repo
  oidc_sub_refs              = ["*"]
  state_bucket_arn           = aws_s3_bucket.state.arn
  tags                       = var.tags
}

# sentinel-gha-ci3: the definitive OIDC role that matches the new GitHub numeric-ID
# sub format. Created fresh so the trust policy is applied at creation time (avoiding
# the iam:UpdateAssumeRolePolicy denial that blocks updates on existing roles).
module "gha_ci3" {
  source = "../modules/iam"

  create_eks_roles           = false
  create_github_oidc         = true
  create_oidc_provider       = false
  existing_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
  gha_role_name              = "sentinel-gha-ci3"
  github_org                 = var.github_org
  github_repo                = var.github_repo
  oidc_sub_refs              = ["*"]
  oidc_new_format_subs       = ["repo:${var.github_org}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:*"]
  state_bucket_arn           = aws_s3_bucket.state.arn
  tags                       = var.tags
}
