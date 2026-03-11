data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

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
        Sid    = "TerraformStateObjectsReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::wow-infra-tfstate/wow-infra/terraform.tfstate",
          "arn:aws:s3:::wow-infra-tfstate/wow-infra/terraform.tfstate.tflock"
        ]
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
          "elasticfilesystem:DescribeFileSystems",
          "iam:Get*",
          "iam:List*",
          "logs:Describe*",
          "logs:ListTagsForResource",
          "rds:Describe*",
          "rds:ListTagsForResource",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:ListSecrets",
          "secretsmanager:ListSecretVersionIds",
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
