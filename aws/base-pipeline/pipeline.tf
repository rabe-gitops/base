data "aws_ssm_parameter" "github_token" {
  name = "/${lower(var.PROJECT)}/github/token"
}

data "aws_ssm_parameter" "webhook_secret" {
  name = "/${lower(var.PROJECT)}/webhook/secret"
}

provider "aws" {
  version = "~> 2.54"
  region  = var.AWS_REGION
  profile = var.AWS_PROFILE
}

provider "github" {
  version      = "~> 2.4"
  token        = data.aws_ssm_parameter.github_token.value # set the TF_VAR_GITHUB_TOKEN env variable before!
  organization = var.GITHUB_OWNER
}

# S3 Bucket
resource "aws_s3_bucket" "artifacts_bucket" {
  provider      = aws
  bucket        = "${lower(var.PROJECT)}-artifacts"
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
    Name    = "${lower(var.PROJECT)}-artifacts"
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


# CodeBuild
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
    type            = "CODEPIPELINE"
    git_clone_depth = 1
    buildspec       = "aws/buildspec.yaml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "hashicorp/terraform:latest"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "PROJECT"
      value = lower(var.PROJECT)
    }
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

# CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  provider = aws
  name     = "${var.PROJECT}CodePipelineRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {
    Name    = "${var.PROJECT}CodePipelineRole"
    Project = lower(var.PROJECT)
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  provider = aws
  name     = "${var.PROJECT}CodePipelinePolicy"
  role     = aws_iam_role.codepipeline_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.artifacts_bucket.arn}",
        "${aws_s3_bucket.artifacts_bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_codepipeline" "codepipeline" {
  provider   = aws
  name       = "${lower(var.PROJECT)}-pipeline"
  role_arn   = aws_iam_role.codepipeline_role.arn
  depends_on = [aws_codebuild_project.codebuild]

  artifact_store {
    location = aws_s3_bucket.artifacts_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Checkout"
      category         = "Source"
      run_order        = 1
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        PollForSourceChanges = false
        Owner                = var.GITHUB_OWNER
        Repo                 = github_repository.infrastructure_repo.name
        Branch               = var.GITHUB_BRANCH
        OAuthToken           = data.aws_ssm_parameter.github_token.value
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "PlanOrApplyOrDestroy"
      category         = "Build"
      run_order        = 2
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.codebuild.name
      }
    }
  }

  tags = {
    Name    = "${lower(var.PROJECT)}-pipeline"
    Project = lower(var.PROJECT)
  }
}

# Webhooks
resource "aws_codepipeline_webhook" "codepipeline_webhook" {
  provider        = aws
  name            = "${lower(var.PROJECT)}-pipeline-webhook"
  authentication  = "GITHUB_HMAC"
  target_action   = "Source"
  target_pipeline = aws_codepipeline.codepipeline.name

  authentication_configuration {
    secret_token = data.aws_ssm_parameter.webhook_secret.value
  }

  filter {
    json_path    = "$.ref"
    match_equals = "refs/heads/${var.GITHUB_BRANCH}"
  }
}

resource "aws_codebuild_webhook" "codebuild_webhook" {
  project_name = aws_codebuild_project.codebuild.name
  secret = data.aws_ssm_parameter.webhook_secret.value

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PULL_REQUEST_CREATED"
    }

    filter {
      type    = "HEAD_REF"
      pattern = "master"
    }
  }
}


# GitHub
resource "github_repository" "infrastructure_repo" {
  provider    = github
  name        = var.GITHUB_REPOSITORY
  description = "Repository containing the IaC files for the Rabe GitOps resources"

  private = false

  template {
    owner      = "rabe-gitops"
    repository = "base"
  }
}

resource "github_repository_webhook" "repository_deploy_webhook" {
  provider   = github
  repository = github_repository.infrastructure_repo.name

  configuration {
    url          = aws_codepipeline_webhook.codepipeline_webhook.url
    content_type = "json"
    insecure_ssl = true
    secret       = data.aws_ssm_parameter.webhook_secret.value
  }

  events = ["push"]
}

resource "github_repository_webhook" "repository_validate_webhook" {
  provider   = github
  repository = github_repository.infrastructure_repo.name

  configuration {
    url          = aws_codebuild_webhook.codebuild_webhook.url
    content_type = "json"
    insecure_ssl = true
    secret       = data.aws_ssm_parameter.webhook_secret.value
  }

  events = ["push"]
}

