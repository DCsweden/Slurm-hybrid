provider "aws" {
  region = var.aws_region
}

provider "google" {
  project = var.gcp_project_id
}

data "aws_caller_identity" "current" {}

data "google_project" "current" {
  project_id = var.gcp_project_id
}
