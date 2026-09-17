terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    # Partial backend: remaining values are passed by GitHub Actions
    #   -backend-config="bucket=..."
    #   -backend-config="key=sentinel/terraform.tfstate"
    #   -backend-config="region=us-east-2"
    #   -backend-config="dynamodb_table=sentinel-tfstate-lock"
    #   -backend-config="encrypt=true"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}
