variable "region" {
  description = "AWS region. Challenge constraint: us-east-2."
  type        = string
  default     = "us-east-2"
}

variable "github_org" {
  description = "GitHub org or user. Set from GitHub Actions (github.repository_owner)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name. Set from GitHub Actions."
  type        = string
}

variable "gha_role_name" {
  description = "OIDC deploy role. Must use sentinel- prefix."
  type        = string
  default     = "sentinel-gha"
}

variable "create_oidc_provider" {
  description = "Create token.actions.githubusercontent.com OIDC provider. Set false if it already exists."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN when create_oidc_provider is false."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default = {
    Project     = "rapyd-sentinel"
    Environment = "poc"
    ManagedBy   = "terraform"
  }
}
