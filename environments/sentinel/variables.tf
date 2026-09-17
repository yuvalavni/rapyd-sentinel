variable "region" {
  description = "AWS region. Challenge constraint: us-east-2."
  type        = string
  default     = "us-east-2"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version for both clusters."
  type        = string
  default     = "1.31"
}

variable "gateway_vpc_cidr" {
  description = "CIDR for vpc-gateway."
  type        = string
  default     = "10.0.0.0/16"
}

variable "backend_vpc_cidr" {
  description = "CIDR for vpc-backend."
  type        = string
  default     = "10.1.0.0/16"
}

variable "node_instance_types" {
  description = "Managed node instance types."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired nodes per cluster. Kept at 1 for cost."
  type        = number
  default     = 1
}

variable "gha_role_name" {
  description = "Existing GitHub Actions role created by bootstrap."
  type        = string
  default     = "sentinel-gha"
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
