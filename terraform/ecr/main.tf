# ============================================================================
# Terraform Configuration for AWS ECR Repositories
# Phase 3: Container Registry Setup
# 
# This creates 5 ECR repositories for the retail store microservices:
#   - retail-store-ui
#   - retail-store-catalog
#   - retail-store-cart
#   - retail-store-orders
#   - retail-store-checkout
# ============================================================================

# ----------------------------------------------------------------------------
# Terraform Configuration
# ----------------------------------------------------------------------------
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ----------------------------------------------------------------------------
# AWS Provider Configuration
# ----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Phase       = "3-ECR"
    }
  }
}

# ----------------------------------------------------------------------------
# Data Source: Get current AWS account ID
# ----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# ----------------------------------------------------------------------------
# Local Variables
# ----------------------------------------------------------------------------
locals {
  # List of microservices that need ECR repositories
  microservices = [
    "ui",
    "catalog",
    "cart",
    "orders",
    "checkout"
  ]

  # ECR registry URL
  ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

# ----------------------------------------------------------------------------
# ECR Repositories
# Creates one repository for each microservice
# ----------------------------------------------------------------------------
resource "aws_ecr_repository" "services" {
  for_each = toset(local.microservices)

  name                 = "${var.ecr_repo_prefix}-${each.key}"
  image_tag_mutability = var.image_tag_mutability

  # Enable image scanning on push for security
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption configuration
  encryption_configuration {
    encryption_type = "AES256"
  }

  # Force delete repository even if it contains images
  # WARNING: Set to false in production!
  force_delete = var.force_delete

  tags = {
    Name        = "${var.ecr_repo_prefix}-${each.key}"
    Service     = each.key
    Description = "ECR repository for ${each.key} microservice"
  }
}

# ----------------------------------------------------------------------------
# ECR Lifecycle Policy
# Automatically clean up old/untagged images to save costs
# ----------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.image_retention_count} images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = var.image_retention_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
