terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-south-1"
}

terraform {
  backend "s3" {
    bucket = "global-logic-devops-training"
    key    = "backend/eks/terraform.tfstate"
    region = "ap-south-1"
  }
}