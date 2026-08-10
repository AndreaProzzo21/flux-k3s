terraform {
  required_version = ">= 1.7"
  
  backend "s3" {
    bucket         = "lab-flux-k3s-terraform-state"
    key            = "cluster/terraform.tfstate" # Unica chiave per tutto il cluster
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.region
}
