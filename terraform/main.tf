provider "aws" {
  region = var.aws_region
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

resource "random_password" "db" {
  count   = var.db_password == "" ? 1 : 0
  length  = 24
  special = false
}

locals {
  cluster_name       = var.project_name
  db_password        = var.db_password != "" ? var.db_password : random_password.db[0].result
  allowed_ssh_cidr   = var.allowed_ssh_cidr != "" ? var.allowed_ssh_cidr : "0.0.0.0/0"
  github_ci_sa_email = var.github_ci_service_account_email != "" ? var.github_ci_service_account_email : "github-slurm-hybrid-ci@${var.gcp_project_id}.iam.gserviceaccount.com"

  login_hostname       = "login"
  ctrl1_hostname       = "ctrl1"
  ctrl2_hostname       = "ctrl2"
  aws_compute_hostname = "aws-compute"
  gcp_compute_hostname = "gcp-compute"
}

module "aws" {
  source = "./modules/aws"

  project_name             = var.project_name
  cluster_name             = local.cluster_name
  aws_region               = var.aws_region
  vpc_cidr                 = var.aws_vpc_cidr
  gcp_vpc_cidr             = var.gcp_vpc_cidr
  ssh_public_key           = var.ssh_public_key
  slurm_version            = var.slurm_version
  db_password              = local.db_password
  allowed_ssh_cidr         = local.allowed_ssh_cidr
  instance_type_login      = var.instance_type_login
  instance_type_controller = var.instance_type_controller
  instance_type_compute    = var.instance_type_aws_compute

  login_hostname       = local.login_hostname
  ctrl1_hostname       = local.ctrl1_hostname
  ctrl2_hostname       = local.ctrl2_hostname
  compute_hostname     = local.aws_compute_hostname
  gcp_compute_hostname = local.gcp_compute_hostname
  gcp_project_id       = var.gcp_project_id
  gcp_zone             = var.gcp_zone
}

module "gcp" {
  source = "./modules/gcp"

  project_id                      = var.gcp_project_id
  project_name                    = var.project_name
  cluster_name                    = local.cluster_name
  region                          = var.gcp_region
  zone                            = var.gcp_zone
  vpc_cidr                        = var.gcp_vpc_cidr
  aws_vpc_cidr                    = var.aws_vpc_cidr
  ssh_public_key                  = var.ssh_public_key
  slurm_version                   = var.slurm_version
  instance_type_compute           = var.instance_type_gcp_compute
  compute_hostname                = local.gcp_compute_hostname
  github_ci_service_account_email = local.github_ci_sa_email
  aws_vpn_peer_ip                 = aws_vpn_connection.gcp.tunnel1_address
  vpn_shared_secret               = module.aws.vpn_preshared_key
}
