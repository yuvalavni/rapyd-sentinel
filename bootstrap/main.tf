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

resource "aws_dynamodb_table" "lock" {
  name         = "sentinel-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(var.tags, {
    Name = "sentinel-tfstate-lock"
  })
}

module "gha" {
  source = "../modules/iam"

  create_eks_roles           = false
  create_github_oidc         = true
  create_oidc_provider       = var.create_oidc_provider
  existing_oidc_provider_arn = var.existing_oidc_provider_arn
  gha_role_name              = var.gha_role_name
  github_org                 = var.github_org
  github_repo                = var.github_repo
  oidc_sub_refs = [
    "ref:refs/heads/main",
    "environment:aws",
    "environment:bootstrap",
  ]
  state_bucket_arn     = aws_s3_bucket.state.arn
  state_lock_table_arn = aws_dynamodb_table.lock.arn
  tags                 = var.tags
}
