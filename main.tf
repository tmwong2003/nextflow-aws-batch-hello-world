#
# Variables and external data sources
#

variable "service_name" {
  default = "nextflow"
}

variable "aws_region" {
  default = "us-west-2"
}

variable "aws_resource_tags" {
  default = {
    Owner = "tmwong"
  }
  type = map(string)
}

#
# AWS provider configuration
#

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.aws_resource_tags, {
      Project = var.service_name
    })
  }
}

#
# Batch compute environment and job queue configuration
#

resource "aws_batch_compute_environment" "nf_ec2_ce" {
  name_prefix = "${var.service_name}-"

  compute_resources {
    allocation_strategy = "BEST_FIT_PROGRESSIVE"

    instance_role = aws_iam_instance_profile.nf_ecs_instance_profile.arn

    instance_type = [
      "default_arm64",
    ]

    max_vcpus = 4
    min_vcpus = 0

    security_group_ids = [
      data.aws_security_group.nf_sg.id,
    ]

    subnets = data.aws_subnets.nf_subnets.ids

    type = "EC2"
  }

  service_role = aws_iam_role.nf_batch_service_role.arn

  type = "MANAGED"

  depends_on = [
    # Required to ensure that Batch can manage other AWS services on our behalf.
    # Annoyingly, if we do not make an explicit dependency,
    # Batch may silently fail to complete configuration of the downstream ECS cluster
    # because Terraform has not yet attached the AWSBatchServiceRole policy
    # to the Batch service role.
    aws_iam_role_policy_attachment.nf_batch_service_role_batch_service_policy
  ]

  lifecycle {
    # Required to decouple compute environment updates
    # (e.g., changing instance types)
    # from the job queue
    create_before_destroy = true
  }
}

resource "aws_batch_job_queue" "nf_ec2_job_queue" {
  name  = var.service_name
  state = "ENABLED"

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.nf_ec2_ce.arn
  }

  priority = 1
}

#
# IAM configuration
#

# Batch service role

# Allow the Batch service to assume the Batch service role
data "aws_iam_policy_document" "nf_batch_role_policy_document" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["batch.amazonaws.com"]
    }
  }
}

# Create the Batch service role
resource "aws_iam_role" "nf_batch_service_role" {
  name               = "${var.service_name}-BatchServiceRole"
  assume_role_policy = data.aws_iam_policy_document.nf_batch_role_policy_document.json
}

# Attach the AWS managed Batch service role policy to the Batch service role.
# Enables Batch to manage other AWS services on our behalf,
# (e.g., the EC2 for auto-scaling and instance launching, ECS cluster creating, etc.)
resource "aws_iam_role_policy_attachment" "nf_batch_service_role_batch_service_policy" {
  role       = aws_iam_role.nf_batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# ECS instance role

# Allow the EC2 service to assume the ECS instance role
data "aws_iam_policy_document" "nf_ecs_role_policy_document_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "nf_ecs_role_policy_document_s3_access" {
  name = "${var.service_name}-EcsS3AccessPolicy"

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

# Create the ECS instance role
resource "aws_iam_role" "nf_ecs_instance_role" {
  name               = "${var.service_name}-EcsInstanceRole"
  assume_role_policy = data.aws_iam_policy_document.nf_ecs_role_policy_document_assume_role.json
}

# Attach the AWS managed ECS for EC2 role policy to the ECS instance role.
# Enables EC2 instances to connect to our cluster
# and register themselves with the ECS control plane.
resource "aws_iam_role_policy_attachment" "nf_ecs_instance_role_ecs_for_ec2_policy" {
  role       = aws_iam_role.nf_ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "nf_ecs_instance_role_s3_access_policy" {
  role       = aws_iam_role.nf_ecs_instance_role.name
  policy_arn = aws_iam_policy.nf_ecs_role_policy_document_s3_access.arn
}

# Create the ECS instance profile to allow EC2 instances to assume the ECS instance role
resource "aws_iam_instance_profile" "nf_ecs_instance_profile" {
  name_prefix = "${var.service_name}-"
  role        = aws_iam_role.nf_ecs_instance_role.name
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
#

module "nf_s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "tmwong-${var.service_name}-scratch"

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
