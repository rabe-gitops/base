# S3 Bucket
resource "aws_s3_bucket" "s3_terraform_state_bucket" {
  provider      = aws
  bucket        = "${lower(var.PROJECT)}-terraform-state"
  acl           = "private"
  force_destroy = true

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name    = "${lower(var.PROJECT)}-terraform-state"
    Project = lower(var.PROJECT)
  }
}


# DynamoDB Table
resource "aws_dynamodb_table" "dynamodb_terraform_lock_table" {
  provider     = aws
  name         = "${lower(var.PROJECT)}-terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "${lower(var.PROJECT)}-terraform-lock"
    Project = lower(var.PROJECT)
  }
}

# GitHub
resource "github_repository" "infrastructure_repo" {
  provider    = github
  name        = var.GITHUB_REPOSITORY
  description = "Repository containing the IaC files for the Rabe GitOps resources"

  private = var.GITHUB_PRIVATE
}

resource "github_repository_webhook" "repository_webhook" {
  provider   = github
  repository = github_repository.infrastructure_repo.name

  configuration {
    url          = aws_codebuild_webhook.codebuild_webhook.url
    content_type = "json"
    insecure_ssl = true
    secret       = aws_codebuild_webhook.codebuild_webhook.secret
  }

  events = ["push", "pull_request"]
}

resource "github_branch_protection" "branch_protection" {
  repository     = github_repository.infrastructure_repo.name
  branch         = var.GITHUB_BRANCH
  enforce_admins = false

  required_status_checks {
    strict = false
    # contexts = [""]
  }
}

# CodeBuild
resource "aws_codebuild_source_credential" "codebuild_source_credential" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = data.aws_ssm_parameter.github_token.value
}

resource "aws_iam_role" "codebuild_role" {
  provider = aws
  name     = "${var.PROJECT}CodeBuildRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {
    Name    = "${var.PROJECT}CodeBuildRole"
    Project = lower(var.PROJECT)
  }
}

resource "aws_iam_role_policy_attachment" "codebuild_role_policy_attachment" {
  provider   = aws
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_codebuild_project" "codebuild" {
  provider      = aws
  name          = "${lower(var.PROJECT)}-codebuild"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 120

  source {
    type                = "GITHUB"
    location            = github_repository.infrastructure_repo.http_clone_url
    git_clone_depth     = 1
    buildspec           = "aws/buildspec.yaml"
    report_build_status = true
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "hashicorp/terraform:latest"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "${lower(var.PROJECT)}-loggroup"
      stream_name = "terraform"
    }
  }

  tags = {
    Name    = "${lower(var.PROJECT)}-codebuild"
    Project = lower(var.PROJECT)
  }
}

resource "aws_codebuild_webhook" "codebuild_webhook" {
  project_name = aws_codebuild_project.codebuild.name

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH,PULL_REQUEST_CREATED"
    }

    filter {
      type    = "HEAD_REF"
      pattern = var.GITHUB_BRANCH
    }
  }
}
