terraform {

  backend "s3" {}

  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.19"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 2.12"
    }
  }
}

variable "name" {
  type        = string
  description = "name for the resources"
}

variable "environment" {
  type        = string
  description = "environment for the resources"
  default = "development"
}

variable "image_tag_api" {
  type        = string
  description = "container image tag"
}

variable "image_tag_web" {
  type        = string
  description = "container image tag"
}

locals {
  ns = "${var.name}-${var.environment}"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_ecr_authorization_token" "token" {}

provider "aws" {}

provider "docker" {
  registry_auth {
    address  = format("%v.dkr.ecr.%v.amazonaws.com", data.aws_caller_identity.current.account_id, data.aws_region.current.name)
    username = data.aws_ecr_authorization_token.token.user_name
    password = data.aws_ecr_authorization_token.token.password
  }
}

module "docker_image_api" {
  source = "terraform-aws-modules/lambda/aws//modules/docker-build"

  create_ecr_repo = true
  ecr_repo        = local.ns
  image_tag       = var.image_tag_api
#  source_path     = "../../Dockerfile"
  docker_file_path = "../../Dockerfile.api"
}

module "docker_image_web" {
  source = "terraform-aws-modules/lambda/aws//modules/docker-build"

  create_ecr_repo = true
  ecr_repo        = local.ns
  image_tag       = var.image_tag_web
#  source_path     = "../../"
  docker_file_path = "../../Dockerfile.web"
}

module "lambda_function_from_container_image_api" {
  source = "terraform-aws-modules/lambda/aws"

  function_name              = local.ns
  description                = "Ephemeral preview environment for: ${local.ns}"
  create_package             = false
  package_type               = "Image"
  image_uri                  = module.docker_image_api.image_uri
  architectures              = ["x86_64"]
  create_lambda_function_url = true
  lambda_role = "${local.ns}-api-role"
  logging_log_group = "/aws/lambda/api/${local.ns}"
}

module "lambda_function_from_container_image_web" {
  source = "terraform-aws-modules/lambda/aws"

  function_name              = local.ns
  description                = "Ephemeral preview environment for: ${local.ns}"
  create_package             = false
  package_type               = "Image"
  image_uri                  = module.docker_image_web.image_uri
  architectures              = ["x86_64"]
  create_lambda_function_url = true
  lambda_role = "${local.ns}-web-role"
  logging_log_group = "/aws/lambda/web/${local.ns}"
}


output "endpoint_url_api" {
  value = module.lambda_function_from_container_image_api.lambda_function_url
}

output "endpoint_url_web" {
  value = module.lambda_function_from_container_image_web.lambda_function_url
}