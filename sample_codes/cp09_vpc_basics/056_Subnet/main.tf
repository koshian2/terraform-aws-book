terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }

  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.8.0"
    }
  }  
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

provider "aws" {
  profile = var.aws_profile_name
}

variable "vpc_cidr_block" {
  description = "CIDR block of VPC"
  type        = string
  default     = "10.32.0.0/16"
}

variable "vpc_name" {
  description = "Name of VPC"
  type        = string
  default     = "terraform-book-vpc"
}

resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr_block
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name = var.vpc_name
  }
}

resource "aws_subnet" "public" {
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = cidrsubnet(aws_vpc.main.cidr_block, 4, 0)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 0)
  availability_zone               = "ap-northeast-1a"
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  enable_resource_name_dns_a_record_on_launch    = true
  enable_resource_name_dns_aaaa_record_on_launch = true

  tags = {
    Name = "${var.vpc_name}-public-1"
  }
}