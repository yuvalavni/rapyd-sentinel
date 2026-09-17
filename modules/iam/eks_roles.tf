locals {
  cluster_name_ok = !var.create_eks_roles || startswith(var.cluster_role_name, "eks-")
  node_name_ok    = !var.create_eks_roles || startswith(var.node_role_name, "eks-")
  gha_name_ok     = !var.create_github_oidc || startswith(var.gha_role_name, "sentinel-")
}

resource "terraform_data" "role_prefix_guard" {
  lifecycle {
    precondition {
      condition     = local.cluster_name_ok && local.node_name_ok && local.gha_name_ok
      error_message = "EKS roles must use prefix eks-; GitHub deploy role must use prefix sentinel-."
    }
  }
}

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    sid     = "EKSAssume"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  count = var.create_eks_roles ? 1 : 0

  name               = var.cluster_role_name
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  description        = "EKS control plane role (prefix eks- required by challenge IAM guardrail)."
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  count = var.create_eks_roles ? 1 : 0

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "node_assume" {
  statement {
    sid     = "EC2Assume"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nodes" {
  count = var.create_eks_roles ? 1 : 0

  name               = var.node_role_name
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  description        = "EKS managed node role (prefix eks- required by challenge IAM guardrail)."
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "nodes_worker" {
  count = var.create_eks_roles ? 1 : 0

  role       = aws_iam_role.nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "nodes_cni" {
  count = var.create_eks_roles ? 1 : 0

  role       = aws_iam_role.nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "nodes_ecr" {
  count = var.create_eks_roles ? 1 : 0

  role       = aws_iam_role.nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "nodes_ssm" {
  count = var.create_eks_roles ? 1 : 0

  # Optional: SSM Session Manager for break-glass without SSH/public EC2.
  role       = aws_iam_role.nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
