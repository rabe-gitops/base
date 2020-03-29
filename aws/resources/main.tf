terraform {
  backend "s3" {} # 'backend-config' options to be passed at runtime!
}

provider "aws" {
  version = "~> 2.54"
  region  = var.AWS_REGION
}

# provider "github" {
#   version      = "~> 2.4"
#   token        = data.aws_ssm_parameter.github_token.value
#   organization = var.GITHUB_OWNER
# }

module "network" {
  source = "./modules/network"

  PROJECT           = var.PROJECT
  AWS_REGION        = var.AWS_REGION
  VPC_CIDR          = var.VPC_CIDR
  DOMAIN_NAME       = var.DOMAIN_NAME
  PUBLIC_SN_A_CIDR  = var.PUBLIC_SN_A_CIDR
  PUBLIC_SN_B_CIDR  = var.PUBLIC_SN_B_CIDR
  PRIVATE_SN_A_CIDR = var.PRIVATE_SN_A_CIDR
  PRIVATE_SN_B_CIDR = var.PRIVATE_SN_B_CIDR
}
