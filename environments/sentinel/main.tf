data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
  gha_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.gha_role_name}"
}

module "iam_gateway" {
  source = "../../modules/iam"

  create_eks_roles   = true
  create_github_oidc = false
  cluster_role_name  = "eks-gateway-cluster"
  node_role_name     = "eks-gateway-nodes"
  tags               = var.tags
}

module "iam_backend" {
  source = "../../modules/iam"

  create_eks_roles   = true
  create_github_oidc = false
  cluster_role_name  = "eks-backend-cluster"
  node_role_name     = "eks-backend-nodes"
  tags               = var.tags
}

module "vpc_gateway" {
  source = "../../modules/vpc"

  name         = "vpc-gateway"
  cidr_block   = var.gateway_vpc_cidr
  azs          = local.azs
  cluster_name = "eks-gateway"
  tags         = var.tags
}

module "vpc_backend" {
  source = "../../modules/vpc"

  name         = "vpc-backend"
  cidr_block   = var.backend_vpc_cidr
  azs          = local.azs
  cluster_name = "eks-backend"
  tags         = var.tags
}

module "peering" {
  source = "../../modules/vpc-peering"

  name             = "sentinel-gateway-backend"
  requester_vpc_id = module.vpc_gateway.vpc_id
  accepter_vpc_id  = module.vpc_backend.vpc_id
  requester_cidr   = module.vpc_gateway.cidr_block
  accepter_cidr    = module.vpc_backend.cidr_block
  requester_route_table_ids = [
    module.vpc_gateway.public_route_table_id,
    module.vpc_gateway.private_route_table_id,
  ]
  accepter_route_table_ids = [
    module.vpc_backend.public_route_table_id,
    module.vpc_backend.private_route_table_id,
  ]
  tags = var.tags
}

module "eks_gateway" {
  source = "../../modules/eks"

  cluster_name           = "eks-gateway"
  kubernetes_version     = var.kubernetes_version
  cluster_role_arn       = module.iam_gateway.cluster_role_arn
  node_role_arn          = module.iam_gateway.node_role_arn
  subnet_ids             = module.vpc_gateway.private_subnet_ids
  node_subnet_ids        = module.vpc_gateway.private_subnet_ids
  vpc_cidr               = module.vpc_gateway.cidr_block
  peer_ingress_cidrs     = ["0.0.0.0/0"]
  instance_types         = var.node_instance_types
  desired_size           = var.node_desired_size
  deployer_principal_arn = local.gha_role_arn
  tags                   = var.tags

  depends_on = [module.peering]
}

module "eks_backend" {
  source = "../../modules/eks"

  cluster_name           = "eks-backend"
  kubernetes_version     = var.kubernetes_version
  cluster_role_arn       = module.iam_backend.cluster_role_arn
  node_role_arn          = module.iam_backend.node_role_arn
  subnet_ids             = module.vpc_backend.private_subnet_ids
  node_subnet_ids        = module.vpc_backend.private_subnet_ids
  vpc_cidr               = module.vpc_backend.cidr_block
  peer_ingress_cidrs     = [module.vpc_gateway.cidr_block]
  instance_types         = var.node_instance_types
  desired_size           = var.node_desired_size
  deployer_principal_arn = local.gha_role_arn
  tags                   = var.tags

  depends_on = [module.peering]
}
