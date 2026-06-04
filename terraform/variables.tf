variable "project_name" {
  description = "Prefix for resource names and Slurm cluster name"
  type        = string
  default     = "slurm-hybrid"
}

variable "aws_region" {
  description = "AWS region for login, controllers, and AWS compute"
  type        = string
  default     = "eu-north-1"
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for compute node"
  type        = string
  default     = "europe-north2"
}

variable "gcp_zone" {
  description = "GCP zone for compute node (Stockholm)"
  type        = string
  default     = "europe-north2-a"
}

variable "ssh_public_key" {
  description = "SSH public key for all nodes (user slurmadmin)"
  type        = string
}

variable "slurm_version" {
  description = "Slurm version to install via bootstrap (e.g. 24.05.3)"
  type        = string
  default     = "24.05.3"
}

variable "instance_type_login" {
  type    = string
  default = "t3.medium"
}

variable "instance_type_controller" {
  type    = string
  default = "t3.medium"
}

variable "instance_type_aws_compute" {
  type    = string
  default = "t3.large"
}

variable "instance_type_gcp_compute" {
  type    = string
  default = "e2-standard-4"
}

variable "aws_vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "gcp_vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "db_password" {
  description = "MariaDB password for slurmdbd (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH to login node"
  type        = string
  default     = "0.0.0.0/0"
}

variable "github_ci_service_account_email" {
  description = "GitHub Actions GCP SA email for IAP bootstrap (default: github-slurm-hybrid-ci@PROJECT)"
  type        = string
  default     = ""
}
