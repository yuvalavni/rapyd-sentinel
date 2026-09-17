variable "create_eks_roles" {
  description = "Create the EKS cluster and node IAM roles."
  type        = bool
  default     = false
}

variable "cluster_role_name" {
  description = "IAM role name for the EKS control plane. Must start with eks-."
  type        = string
  default     = ""
}

variable "node_role_name" {
  description = "IAM role name for EKS worker nodes. Must start with eks-."
  type        = string
  default     = ""
}

variable "create_github_oidc" {
  description = "Create the GitHub OIDC provider and sentinel-gha deploy role."
  type        = bool
  default     = false
}

variable "gha_role_name" {
  description = "IAM role assumed by GitHub Actions via OIDC. Must start with sentinel-."
  type        = string
  default     = "sentinel-gha"
}

variable "github_org" {
  description = "GitHub organization or user that owns the repo."
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name (without org)."
  type        = string
  default     = ""
}

variable "oidc_sub_refs" {
  description = "Allowed GitHub OIDC sub suffixes after repo:org/name: (e.g. environment:aws, ref:refs/heads/main)."
  type        = list(string)
  default     = ["*"]
}

variable "oidc_new_format_subs" {
  description = "Raw OIDC sub patterns for the new GitHub format (owner@id/repo@id). Use trailing * for safety. These are appended verbatim to StringLike values."
  type        = list(string)
  default     = []
}

variable "state_bucket_arn" {
  description = "Terraform state S3 bucket ARN granted to sentinel-gha."
  type        = string
  default     = ""
}

variable "state_lock_table_arn" {
  description = "Terraform lock DynamoDB table ARN granted to sentinel-gha."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to IAM roles."
  type        = map(string)
  default     = {}
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if one already exists in the account."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN when create_oidc_provider is false."
  type        = string
  default     = ""
}
