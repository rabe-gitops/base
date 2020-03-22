terraform {
  backend "s3" {} # 'backend-config' options to be passed at runtime!
}

provider "aws" {
  version = "~> 2.54"
  region  = var.AWS_REGION
}

resource "aws_iam_user" "test_user" {
  name = "test_user"
  path = "/"
}
