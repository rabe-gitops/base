data "aws_ssm_parameter" "github_token" {
  name = "/${lower(var.PROJECT)}/github/token"
}
