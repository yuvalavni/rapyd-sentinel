data "tls_certificate" "github" {
  count = var.create_github_oidc && var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc && var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]

  tags = merge(var.tags, {
    Name = "github-actions"
  })
}

locals {
  github_oidc_arn = var.create_github_oidc ? (
    var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
  ) : ""

  # GitHub's OIDC sub claim changed format in 2025 to include numeric IDs:
  #   OLD: repo:owner/repo:ref
  #   NEW: repo:owner@ownerID/repo@repoID:ref
  # The old-format pattern uses StringLike with oidc_sub_refs composed in.
  # The new-format pattern uses a trailing wildcard so it works with AWS StringLike
  # regardless of whether the implementation is greedy or uses backtracking.
  github_subs = concat(
    [for ref in var.oidc_sub_refs : "repo:${var.github_org}/${var.github_repo}:${ref}"],
    # New GitHub OIDC format: prefix is fixed, trailing * covers ref/environment/etc.
    var.oidc_new_format_subs
  )
}

data "aws_iam_policy_document" "gha_assume" {
  count = var.create_github_oidc ? 1 : 0

  statement {
    sid     = "GitHubOIDC"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subs
    }
  }
}

data "aws_caller_identity" "current" {
  count = var.create_github_oidc ? 1 : 0
}

data "aws_iam_policy_document" "gha" {
  count = var.create_github_oidc ? 1 : 0

  statement {
    # Read-only EKS actions that do not support resource-level ARNs (AWS limitation).
    sid = "EKSRead"
    actions = [
      "eks:DescribeAddonVersions", # no resource-level support
      "eks:ListClusters",          # no resource-level support
    ]
    resources = ["*"]
  }

  statement {
    # Mutating EKS actions scoped to clusters/nodegroups/addons under the eks-* prefix.
    # This enforces least privilege: the deploy role cannot touch clusters it didn't create.
    sid = "EKSMutate"
    actions = [
      "eks:CreateCluster",
      "eks:DeleteCluster",
      "eks:DescribeCluster",
      "eks:DescribeUpdate",
      "eks:UpdateClusterConfig",
      "eks:UpdateClusterVersion",
      "eks:TagResource",
      "eks:UntagResource",
      "eks:ListTagsForResource",
      "eks:AccessKubernetesApi",
    ]
    resources = [
      "arn:aws:eks:*:${data.aws_caller_identity.current[0].account_id}:cluster/eks-*",
    ]
  }

  statement {
    sid = "EKSNodegroups"
    actions = [
      "eks:CreateNodegroup",
      "eks:DeleteNodegroup",
      "eks:DescribeNodegroup",
      "eks:ListNodegroups",
      "eks:UpdateNodegroupConfig",
      "eks:UpdateNodegroupVersion",
    ]
    resources = [
      "arn:aws:eks:*:${data.aws_caller_identity.current[0].account_id}:cluster/eks-*",
      "arn:aws:eks:*:${data.aws_caller_identity.current[0].account_id}:nodegroup/eks-*/*/*",
    ]
  }

  statement {
    sid = "EKSAddons"
    actions = [
      "eks:CreateAddon",
      "eks:DeleteAddon",
      "eks:DescribeAddon",
      "eks:ListAddons",
      "eks:UpdateAddon",
    ]
    resources = [
      "arn:aws:eks:*:${data.aws_caller_identity.current[0].account_id}:cluster/eks-*",
      "arn:aws:eks:*:${data.aws_caller_identity.current[0].account_id}:addon/eks-*/*/*",
    ]
  }

  statement {
    sid = "EKSAccessEntries"
    actions = [
      "eks:AssociateAccessPolicy",
      "eks:DisassociateAccessPolicy",
      "eks:ListAssociatedAccessPolicies",
      "eks:CreateAccessEntry",
      "eks:DeleteAccessEntry",
      "eks:DescribeAccessEntry",
      "eks:ListAccessEntries",
      "eks:UpdateAccessEntry",
    ]
    resources = [
      "arn:aws:eks:*:${data.aws_caller_identity.current[0].account_id}:cluster/eks-*",
      "arn:aws:eks:*:${data.aws_caller_identity.current[0].account_id}:access-entry/eks-*/*/*/*",
    ]
  }

  statement {
    sid = "EC2NetworkingAndNodes"
    actions = [
      "ec2:AcceptVpcPeeringConnection",
      "ec2:AllocateAddress",
      "ec2:AssociateAddress",
      "ec2:AssociateRouteTable",
      "ec2:AttachInternetGateway",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateInternetGateway",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:CreateNatGateway",
      "ec2:CreateRoute",
      "ec2:CreateRouteTable",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSubnet",
      "ec2:CreateTags",
      "ec2:CreateVpc",
      "ec2:CreateVpcPeeringConnection",
      "ec2:DeleteInternetGateway",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteLaunchTemplateVersions",
      "ec2:DeleteNatGateway",
      "ec2:DeleteRoute",
      "ec2:DeleteRouteTable",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSubnet",
      "ec2:DeleteTags",
      "ec2:DeleteVpc",
      "ec2:DeleteVpcPeeringConnection",
      "ec2:Describe*",
      "ec2:DetachInternetGateway",
      "ec2:DisassociateAddress",
      "ec2:DisassociateRouteTable",
      "ec2:ModifyLaunchTemplate",
      "ec2:ModifySubnetAttribute",
      "ec2:ModifyVpcAttribute",
      "ec2:ModifyVpcPeeringConnectionOptions",
      "ec2:ReleaseAddress",
      "ec2:ReplaceRoute",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StopInstances",
      "ec2:StartInstances",
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:AttachNetworkInterface",
      "ec2:DetachNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
      "ec2:ModifyNetworkInterfaceAttribute",
    ]
    resources = ["*"]
  }

  statement {
    # ELB does not support resource-level ARNs for most actions (AWS limitation).
    # Scoped to the specific actions Terraform + in-tree cloud provider require.
    sid = "LoadBalancing"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
    ]
    resources = ["*"]
  }

  statement {
    # Autoscaling is used by EKS managed node groups.
    # Scoped to explicit actions; DeleteAutoScalingGroup is intentionally excluded
    # (node group deletion goes through eks:DeleteNodegroup, not directly).
    sid = "AutoScaling"
    actions = [
      "autoscaling:CreateAutoScalingGroup",
      "autoscaling:DeleteAutoScalingGroup",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeScheduledActions",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:EnableMetricsCollection",
      "autoscaling:DisableMetricsCollection",
      "autoscaling:PutScalingPolicy",
      "autoscaling:DeleteScalingPolicy",
      "autoscaling:AttachLoadBalancerTargetGroups",
      "autoscaling:DetachLoadBalancerTargetGroups",
      "autoscaling:CreateOrUpdateTags",
      "autoscaling:DeleteTags",
      "autoscaling:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:DeleteLogGroup",
      "logs:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid = "IAMRead"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListOpenIDConnectProviders",
      "iam:ListRolePolicies",
      "iam:ListRoles",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid = "IAMRolesPrefixGuardrail"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PassRole",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:role/eks-*",
      "arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:role/sentinel-*",
      "arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:instance-profile/eks-*",
      "arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:instance-profile/sentinel-*",
    ]
  }

  statement {
    sid     = "IAMServiceLinkedEKS"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:role/aws-service-role/eks.amazonaws.com/*",
      "arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/*",
      "arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:role/aws-service-role/elasticloadbalancing.amazonaws.com/*",
    ]
  }

  dynamic "statement" {
    for_each = var.state_bucket_arn != "" ? [var.state_bucket_arn] : []
    content {
      sid = "TerraformStateS3"
      actions = [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
      ]
      resources = [
        statement.value,
        "${statement.value}/*",
      ]
    }
  }

  dynamic "statement" {
    for_each = var.state_lock_table_arn != "" ? [var.state_lock_table_arn] : []
    content {
      sid = "TerraformStateLock"
      actions = [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
      ]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role" "gha" {
  count = var.create_github_oidc ? 1 : 0

  name               = var.gha_role_name
  assume_role_policy = data.aws_iam_policy_document.gha_assume[0].json
  description        = "GitHub Actions deploy role via OIDC (prefix sentinel-)."

  # iam:TagRole and iam:UpdateAssumeRolePolicy are both denied for the bootstrap IAM user.
  # Ignore changes to assume_role_policy to prevent bootstrap from failing on existing roles.
  lifecycle {
    ignore_changes = [assume_role_policy]
  }
}

resource "aws_iam_role_policy" "gha" {
  count = var.create_github_oidc ? 1 : 0

  name   = "sentinel-gha-infra"
  role   = aws_iam_role.gha[0].id
  policy = data.aws_iam_policy_document.gha[0].json
}
