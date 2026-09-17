output "region" {
  description = "AWS region."
  value       = var.region
}

output "aws_account_id" {
  description = "AWS account ID."
  value       = data.aws_caller_identity.current.account_id
}

output "gha_role_arn" {
  description = "GitHub Actions role ARN granted cluster-admin on both clusters."
  value       = local.gha_role_arn
}

output "gateway_vpc_id" {
  value = module.vpc_gateway.vpc_id
}

output "backend_vpc_id" {
  value = module.vpc_backend.vpc_id
}

output "gateway_vpc_cidr" {
  value = module.vpc_gateway.cidr_block
}

output "backend_vpc_cidr" {
  value = module.vpc_backend.cidr_block
}

output "peering_connection_id" {
  value = module.peering.peering_connection_id
}

output "eks_gateway_name" {
  value = module.eks_gateway.cluster_name
}

output "eks_backend_name" {
  value = module.eks_backend.cluster_name
}

output "eks_gateway_endpoint" {
  value = module.eks_gateway.cluster_endpoint
}

output "eks_backend_endpoint" {
  value = module.eks_backend.cluster_endpoint
}

output "eks_gateway_security_group_id" {
  value = module.eks_gateway.cluster_security_group_id
}

output "eks_backend_security_group_id" {
  value = module.eks_backend.cluster_security_group_id
}
