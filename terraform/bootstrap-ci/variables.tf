variable "github_repository" {
  description = "GitHub repo in form OWNER/NAME (must match Actions OIDC sub)"
  type        = string
  default     = "DCsweden/Slurm-hybrid"
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  default     = "dcprod"
}

variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "github_oidc_role_name" {
  type    = string
  default = "github-slurm-hybrid-terraform"
}

variable "gcp_ci_service_account_id" {
  type    = string
  default = "github-slurm-hybrid-ci"
}

variable "wif_pool_id" {
  type    = string
  default = "github-pool"
}

variable "wif_provider_id" {
  type    = string
  default = "github-provider"
}

variable "tf_state_bucket" {
  description = "S3 bucket used for Terraform state (scoped in IAM policy)"
  type        = string
  default     = "slurm-hybrid-tfstate"
}

variable "tf_state_lock_table" {
  type    = string
  default = "slurm-hybrid-tflock"
}

variable "create_github_oidc_provider" {
  description = "Set false if account already has token.actions.githubusercontent.com OIDC provider"
  type        = bool
  default     = false
}
