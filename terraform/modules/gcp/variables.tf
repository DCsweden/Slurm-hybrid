variable "project_id" { type = string }
variable "project_name" { type = string }
variable "cluster_name" { type = string }
variable "region" { type = string }
variable "zone" { type = string }
variable "vpc_cidr" { type = string }
variable "aws_vpc_cidr" { type = string }
variable "ssh_public_key" { type = string }
variable "slurm_version" { type = string }
variable "instance_type_compute" { type = string }
variable "compute_hostname" { type = string }

variable "compute_private_ip" {
  type    = string
  default = "10.1.1.10"
}

variable "github_ci_service_account_email" {
  description = "GitHub Actions CI SA (WIF) — granted IAP tunnel access for bootstrap"
  type        = string
  default     = ""
}

variable "aws_vpn_peer_ip" {
  description = "AWS VPN tunnel outside IP (tunnel1_address)"
  type        = string
  default     = ""
}

variable "vpn_shared_secret" {
  description = "IPsec pre-shared key (same as AWS side)"
  type        = string
  sensitive   = true
  default     = ""
}

