data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_iam_role" "github_actions_terraform_plan" {
  name = "wow-infra-github-terraform-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:thekbb/wow-infra:pull_request"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "github_actions_terraform_plan" {
  name = "wow-infra-github-terraform-plan"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateBucketList"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::wow-infra-tfstate"
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "wow-infra/*"
            ]
          }
        }
      },
      {
        Sid    = "TerraformStateObjectReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::wow-infra-tfstate/wow-infra/terraform.tfstate"
      },
      {
        Sid    = "TerraformStateLockObjectReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::wow-infra-tfstate/wow-infra/terraform.tfstate.tflock"
      },
      {
        Sid    = "TerraformPlanReadOnlyAwsApis"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ecs:Describe*",
          "ecs:List*",
          "elasticloadbalancing:Describe*",
          "efs:Describe*",
          "elasticfilesystem:Describe*",
          "iam:Get*",
          "iam:List*",
          "logs:Describe*",
          "logs:ListTagsForResource",
          "rds:Describe*",
          "rds:ListTagsForResource",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:List*",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_terraform_plan" {
  role       = aws_iam_role.github_actions_terraform_plan.name
  policy_arn = aws_iam_policy.github_actions_terraform_plan.arn
}

resource "aws_iam_role" "github_actions_terraform_apply" {
  name = "wow-infra-github-terraform-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:thekbb/wow-infra:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "github_actions_terraform_apply" {
  name = "wow-infra-github-terraform-apply"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateBucketList"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::wow-infra-tfstate"
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "wow-infra/*"
            ]
          }
        }
      },
      {
        Sid    = "TerraformStateObjectReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::wow-infra-tfstate/wow-infra/terraform.tfstate"
      },
      {
        Sid    = "TerraformStateLockObjectReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::wow-infra-tfstate/wow-infra/terraform.tfstate.tflock"
      },
      {
        Sid    = "TerraformReadSupportingApis"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ecs:Describe*",
          "ecs:List*",
          "elasticfilesystem:Describe*",
          "elasticloadbalancing:Describe*",
          "iam:Get*",
          "iam:List*",
          "iam:GetOpenIDConnectProvider",
          "logs:Describe*",
          "logs:ListTagsForResource",
          "rds:Describe*",
          "rds:ListTagsForResource",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:List*",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformManageNetworking"
        Effect = "Allow"
        Action = [
          "ec2:AllocateAddress",
          "ec2:AssociateRouteTable",
          "ec2:AttachInternetGateway",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateInternetGateway",
          "ec2:CreateNatGateway",
          "ec2:CreateRoute",
          "ec2:CreateRouteTable",
          "ec2:CreateSecurityGroup",
          "ec2:CreateSubnet",
          "ec2:CreateTags",
          "ec2:CreateVpc",
          "ec2:DeleteInternetGateway",
          "ec2:DeleteNatGateway",
          "ec2:DeleteRoute",
          "ec2:DeleteRouteTable",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteSubnet",
          "ec2:DeleteTags",
          "ec2:DeleteVpc",
          "ec2:DetachInternetGateway",
          "ec2:DisassociateRouteTable",
          "ec2:ModifySubnetAttribute",
          "ec2:ModifyVpcAttribute",
          "ec2:ReleaseAddress",
          "ec2:ReplaceRoute",
          "ec2:ReplaceRouteTableAssociation",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformManageLoadBalancing"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformManageRdsAndEfs"
        Effect = "Allow"
        Action = [
          "rds:AddTagsToResource",
          "rds:CreateDBInstance",
          "rds:CreateDBSubnetGroup",
          "rds:DeleteDBInstance",
          "rds:DeleteDBSubnetGroup",
          "rds:ModifyDBInstance",
          "rds:ModifyDBSubnetGroup",
          "rds:RemoveTagsFromResource",
          "elasticfilesystem:CreateFileSystem",
          "elasticfilesystem:CreateMountTarget",
          "elasticfilesystem:DeleteFileSystem",
          "elasticfilesystem:DeleteMountTarget",
          "elasticfilesystem:TagResource",
          "elasticfilesystem:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformManageEcs"
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster",
          "ecs:CreateService",
          "ecs:DeleteCluster",
          "ecs:DeleteService",
          "ecs:DeregisterTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:TagResource",
          "ecs:UntagResource",
          "ecs:UpdateService"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformManageLogsAndSecrets"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DeleteRetentionPolicy",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource",
          "secretsmanager:UpdateSecret"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformManageIamRolesAndPolicies"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:CreatePolicy",
          "iam:CreatePolicyVersion",
          "iam:CreateRole",
          "iam:DeletePolicy",
          "iam:DeletePolicyVersion",
          "iam:DeleteRole",
          "iam:DetachRolePolicy",
          "iam:SetDefaultPolicyVersion",
          "iam:TagPolicy",
          "iam:TagRole",
          "iam:UntagPolicy",
          "iam:UntagRole",
          "iam:UpdateAssumeRolePolicy"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformPassEcsExecutionRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/azerothcore-ecs-exec"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_terraform_apply" {
  role       = aws_iam_role.github_actions_terraform_apply.name
  policy_arn = aws_iam_policy.github_actions_terraform_apply.arn
}
