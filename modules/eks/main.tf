resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  access_config {
    authentication_mode = "API"
    # Set to false so Terraform owns ALL access entries explicitly.
    # With true, EKS auto-creates an entry for the caller role, which
    # causes a 409 conflict when Terraform then tries to create aws_eks_access_entry.deployer.
    bootstrap_cluster_creator_admin_permissions = false
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = merge(var.tags, {
    Name = var.cluster_name
  })

  depends_on = [aws_cloudwatch_log_group.cluster]
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_eks_access_entry" "nodes" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.node_role_arn
  type          = "EC2_LINUX"
}

resource "aws_eks_access_entry" "deployer" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.deployer_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "deployer" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.deployer_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.deployer]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  tags = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.node_subnet_ids
  instance_types  = var.instance_types
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  disk_size       = 20

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "general"
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-nodes"
  })

  depends_on = [
    aws_eks_access_entry.nodes,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags

  depends_on = [aws_eks_node_group.this]
}

# In-tree / cloud-provider NLBs (instance targets) hit nodes on the service
# port and the NodePort range. Restrict sources to the peer CIDR (backend)
# or 0.0.0.0/0 (public gateway NLB). Health checks come from this VPC CIDR.
locals {
  cluster_sg    = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  ingress_cidrs = distinct(concat(var.peer_ingress_cidrs, [var.vpc_cidr]))
}

resource "aws_vpc_security_group_ingress_rule" "app" {
  for_each = toset(local.ingress_cidrs)

  security_group_id = local.cluster_sg
  description       = "App port from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = var.app_port
  to_port           = var.app_port
  ip_protocol       = "tcp"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "nodeport" {
  for_each = toset(local.ingress_cidrs)

  security_group_id = local.cluster_sg
  description       = "NodePort range from ${each.value} (NLB instance targets)"
  cidr_ipv4         = each.value
  from_port         = 30000
  to_port           = 32767
  ip_protocol       = "tcp"

  tags = var.tags
}
