# ============================================================================
# Terraform Variables for ECR Configuration
# Phase 3: Container Registry Setup
# ============================================================================

# ----------------------------------------------------------------------------
# Required Variables
# ----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region where ECR repositories will be created"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project (used for tagging)"
  type        = string
  default     = "k8s-kubeadm"
}

# ----------------------------------------------------------------------------
# ECR Configuration Variables
# ----------------------------------------------------------------------------

variable "ecr_repo_prefix" {
  description = "Prefix for ECR repository names (e.g., 'retail-store' creates 'retail-store-ui')"
  type        = string
  default     = "retail-store"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "image_tag_mutability" {
  description = "The tag mutability setting for the repository (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable image scanning on push for security vulnerabilities"
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Allow deletion of repository even if it contains images (use with caution!)"
  type        = bool
  default     = true
}

# ----------------------------------------------------------------------------
# Lifecycle Policy Variables
# ----------------------------------------------------------------------------

variable "image_retention_count" {
  description = "Number of tagged images to retain per repository"
  type        = number
  default     = 30
}

variable "untagged_image_expiry_days" {
  description = "Number of days after which untagged images are deleted"
  type        = number
  default     = 7
}
