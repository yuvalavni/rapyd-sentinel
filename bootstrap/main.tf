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
  gha_role_name              = var.gha_role_name
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
