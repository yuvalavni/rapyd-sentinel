output "cluster_role_arn" {
  description = "EKS cluster IAM role ARN."
  value       = var.create_eks_roles ? aws_iam_role.cluster[0].arn : null
  depends_on = [
    aws_iam_role_policy_attachment.cluster,
  ]
}

output "cluster_role_name" {
  description = "EKS cluster IAM role name."
  value       = var.create_eks_roles ? aws_iam_role.cluster[0].name : null
}

output "node_role_arn" {
  description = "EKS node IAM role ARN."
  value       = var.create_eks_roles ? aws_iam_role.nodes[0].arn : null
  depends_on = [
    aws_iam_role_policy_attachment.nodes_worker,
    aws_iam_role_policy_attachment.nodes_cni,
    aws_iam_role_policy_attachment.nodes_ecr,
    aws_iam_role_policy_attachment.nodes_ssm,
  ]
}

output "node_role_name" {
  description = "EKS node IAM role name."
  value       = var.create_eks_roles ? aws_iam_role.nodes[0].name : null
}

output "gha_role_arn" {
  description = "GitHub Actions deploy role ARN."
  value       = var.create_github_oidc ? aws_iam_role.gha[0].arn : null
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN."
  value       = var.create_github_oidc ? local.github_oidc_arn : null
}
