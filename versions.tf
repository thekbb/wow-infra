terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket       = "wow-infra-tfstate"
    key          = "wow-infra/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.35"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      Application = "world-of-warcraft"
    }
  }
}
