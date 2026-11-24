terraform {
  required_version = ">= 1.14, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 6.71.0" }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
  default_tags { tags = { Project = "entra-graph-private-key-jwt", ManagedBy = "Terraform" } }
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}
variable "aws_profile" {
  type    = string
  default = "develop"
}
variable "certificate_signer_arn" {
  type        = string
  description = "IAM role/user ARN of the operator creating the public certificates; not an STS session ARN."
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_kms_key" "signing" {
  for_each                 = toset(["obo", "m2m"])
  description              = "Private Key JWT Entra ${each.key} certificate credential"
  customer_master_key_spec = "RSA_2048"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 7
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    {
      Sid       = "KeyAdministration", Effect = "Allow",
      Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" },
      Action    = ["kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*", "kms:DeleteAlias", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion"], Resource = "*"
    },
    {
      Sid    = "CertificateCreation", Effect = "Allow", Principal = { AWS = var.certificate_signer_arn },
      Action = ["kms:GetPublicKey", "kms:Sign", "kms:DescribeKey"], Resource = "*"
    },
    {
      Sid       = "AgentCoreIdentitySigning", Effect = "Allow",
      Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" },
      Action    = ["kms:Sign", "kms:DescribeKey"], Resource = "*",
      Condition = {
        StringEquals = { "aws:ResourceAccount" = "$${aws:PrincipalAccount}" }
        StringLike   = { "kms:ViaService" = "bedrock-agentcore-identity.${var.aws_region}.amazonaws.com" }
      }
    }
  ] })
}

resource "aws_kms_alias" "signing" {
  for_each      = aws_kms_key.signing
  name          = "alias/entra-graph-pkjwt-${each.key}"
  target_key_id = each.value.key_id
}

output "key_arns" { value = { for name, key in aws_kms_key.signing : name => key.arn } }

output "settings" { value = { aws_profile = var.aws_profile, aws_region = var.aws_region } }
