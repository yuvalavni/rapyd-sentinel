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

variable "github_owner_id" {
  description = "GitHub owner numeric ID (github.repository_owner_id). Used for new-format OIDC sub claim."
  type        = string
}

variable "github_repo_id" {
  description = "GitHub repository numeric ID (github.repository_id). Used for new-format OIDC sub claim."
  type        = string
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
