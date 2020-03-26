provider "aws" {
  version = "~> 2.54"
  region  = var.AWS_REGION
  profile = var.AWS_PROFILE
}

provider "github" {
  version      = "~> 2.4"
  token        = data.aws_ssm_parameter.github_token.value
  organization = var.GITHUB_OWNER
}
