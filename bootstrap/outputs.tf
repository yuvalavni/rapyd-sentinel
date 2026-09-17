output "aws_account_id" {
  description = "AWS account ID discovered from the bootstrap principal."
  value       = data.aws_caller_identity.current.account_id
}

output "state_bucket" {
  description = "S3 bucket for the sentinel environment Terraform state."
  value       = aws_s3_bucket.state.bucket
}

output "gha_role_arn" {
  description = "Original sentinel-gha role (trust policy is immutable for this IAM user)."
  value       = module.gha.gha_role_arn
}

output "gha_ci_role_arn" {
  description = "Role GitHub Actions assumes via OIDC (sentinel-gha-ci)."
  value       = module.gha_ci.gha_role_arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN (looked up, not created)."
  value       = module.gha.github_oidc_provider_arn
}
