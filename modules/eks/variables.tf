variable "cluster_name" {
  description = "EKS cluster name (eks-gateway or eks-backend)."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "cluster_role_arn" {
  description = "IAM role ARN for the control plane (eks-* prefix)."
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for managed nodes (eks-* prefix)."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the EKS control plane ENIs (private subnets)."
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Private subnets for managed node groups."
  type        = list(string)
}

variable "vpc_cidr" {
  description = "This cluster's VPC CIDR (NLB health checks, intra-VPC)."
  type        = string
}

variable "peer_ingress_cidrs" {
  description = "CIDRs allowed to reach node/NLB target ports (the other VPC, or 0.0.0.0/0 for the public gateway)."
  type        = list(string)
  default     = []
}

variable "app_port" {
  description = "Application TCP port allowed from peer_ingress_cidrs."
  type        = number
  default     = 80
}

variable "instance_types" {
  description = "Managed node instance types."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "desired_size" {
  description = "Desired managed node count."
  type        = number
  default     = 1
}

variable "min_size" {
  description = "Minimum managed node count."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum managed node count."
  type        = number
  default     = 2
}

variable "deployer_principal_arn" {
  description = "IAM principal granted cluster-admin via EKS access entries (sentinel-gha)."
  type        = string
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs that may reach the public EKS API. 0.0.0.0/0 is required for GitHub-hosted runners."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Tags applied to the cluster and node group."
  type        = map(string)
  default     = {}
}
