#
# Variables and external data sources
#

variable "service_name" {
  type    = string
  default = "nextflow"
}

variable "service_owner" {
  type = string
  validation {
    condition     = length(var.service_owner) > 0
    error_message = "Got an empty service owner name."
  }
}

# AWS

variable "aws_region" {
  type    = string
  validation {
    condition     = length(var.aws_region) > 0
    error_message = "Got an empty AWS region."
  }
}

variable "aws_resource_tags" {
  type = map(string)
  default = {
  }
}

# Docker

variable "docker_repository" {
  type    = string
  validation {
    condition     = length(var.docker_repository) > 0
    error_message = "Got an empty Docker repository name."
  }
}

#
# AWS provider configuration
#

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.aws_resource_tags, {
      Owner   = var.service_owner
      Project = var.service_name
    })
  }
}

#
# Batch compute environment and job queue configuration
#

module "nf_batch" {
  source = "terraform-aws-modules/batch/aws"

  # Based on the example from
  # https://github.com/terraform-aws-modules/terraform-aws-batch/blob/57ded354043005e2b0f8e67d85eaa39bedabd682/examples/ec2/main.tf

  # The module attaches AmazonEC2ContainerServiceforEC2Role automatically
  instance_iam_role_name        = "${var.service_name}EcsInstanceRole"
  instance_iam_role_path        = "/batch/"
  instance_iam_role_description = "IAM instance role/profile for AWS Batch ECS instance(s)"
  instance_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonSSMPatchAssociation    = "arn:aws:iam::aws:policy/AmazonSSMPatchAssociation"
    nextflowEcsS3AccessPolicy    = aws_iam_policy.nf_ecs_s3_access_policy.arn
  }
  instance_iam_role_tags = {
    Module = "terraform-aws-modules/batch/aws"
  }
  instance_iam_role_use_name_prefix = false

  # The module attaches AWSBatchServiceRole automatically
  service_iam_role_name        = "${var.service_name}BatchServiceRole"
  service_iam_role_path        = "/batch/"
  service_iam_role_description = "IAM service role for AWS Batch"
  service_iam_role_tags = {
    Module = "terraform-aws-modules/batch/aws"
  }
  service_iam_role_use_name_prefix = false

  compute_environments = {
    nf_ec2_ce = {
      # Unlike the raw aws_batch_compute_environment resource,
      # the module appends a '-' to the prefix automatically.
      name_prefix = "${var.service_name}"
      compute_resources = {
        allocation_strategy = "BEST_FIT_PROGRESSIVE"
        instance_types = [
          "default_arm64",
        ]
        max_vcpus = 4
        min_vcpus = 0
        security_group_ids = [
          data.aws_security_group.nf_sg.id,
        ]
        subnets = data.aws_subnets.nf_subnets.ids
        type    = "EC2"

        # Sets tags on the EC2 instances launched for this compute environment.
        # Tag changes force compute environment replacement
        # which can lead to job queue conflicts.
        # Only specify tags that will be static
        # for the lifetime of the compute environment.
        tags = {
          Name   = var.service_name
          Module = "terraform-aws-modules/batch/aws"
          Type   = "Ec2"
        }
      }
    }
  }

  job_queues = {
    nf_ec2_job_queue = {
      name     = var.service_name
      priority = 1
      state    = "ENABLED"

      compute_environment_order = {
        0 = {
          compute_environment_key = "nf_ec2_ce"
        }
      }

      create_scheduling_policy = false
    }
  }
}

#
# ECR configuration
#

resource "aws_ecr_repository" "nf_ecr_repository" {
  name = "${var.service_owner}/${var.docker_repository}"
  encryption_configuration {
    encryption_type = "AES256"
  }
  force_delete         = true
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

#
# IAM configuration
#

resource "aws_iam_policy" "nf_ecs_s3_access_policy" {
  name = "${var.service_name}EcsS3Access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Effect = "Allow"
        Resource = [
          module.nf_s3_bucket.s3_bucket_arn,
          "${module.nf_s3_bucket.s3_bucket_arn}/*",
        ]
      }
    ]
  })
}

#
# Network configuration.
# Assumes that you have tagged your default VPC, subnets, and security groups with "Name: Default".
#

data "aws_vpc" "nf_vpc" {
  filter {
    name   = "tag:Name"
    values = ["Default"]
  }
}

data "aws_security_group" "nf_sg" {
  vpc_id = data.aws_vpc.nf_vpc.id
  filter {
    name   = "tag:Name"
    values = ["Default"]
  }
}

data "aws_subnets" "nf_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.nf_vpc.id]
  }
  filter {
    name   = "tag:Name"
    values = ["Default"]
  }
}

#
# S3 configuration
# https://github.com/terraform-aws-modules/terraform-aws-s3-bucket
#

module "nf_s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "${var.service_owner}-${var.service_name}-scratch"

  acl                      = "private"
  control_object_ownership = true
  force_destroy            = true
  object_ownership         = "ObjectWriter"
  putin_khuylo             = true
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}
