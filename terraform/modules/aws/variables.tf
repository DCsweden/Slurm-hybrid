variable "project_name" { type = string }
variable "cluster_name" { type = string }
variable "aws_region" { type = string }
variable "vpc_cidr" { type = string }
variable "gcp_vpc_cidr" { type = string }
variable "ssh_public_key" { type = string }
variable "slurm_version" { type = string }
variable "db_password" { type = string }
variable "allowed_ssh_cidr" { type = string }
variable "instance_type_login" { type = string }
variable "instance_type_controller" { type = string }
variable "instance_type_compute" { type = string }

variable "login_hostname" { type = string }
variable "ctrl1_hostname" { type = string }
variable "ctrl2_hostname" { type = string }
variable "compute_hostname" { type = string }
variable "gcp_compute_hostname" { type = string }

# Static private IPs (must match slurm.conf NodeAddr)
variable "login_private_ip" {
  type    = string
  default = "10.0.1.10"
}
variable "ctrl1_private_ip" {
  type    = string
  default = "10.0.1.11"
}
variable "ctrl2_private_ip" {
  type    = string
  default = "10.0.1.12"
}
variable "compute_private_ip" {
  type    = string
  default = "10.0.2.10"
}
variable "gcp_compute_private_ip" {
  type    = string
  default = "10.1.1.10"
}

variable "gcp_project_id" {
  type    = string
  default = ""
}

variable "gcp_zone" {
  type    = string
  default = "europe-north2-a"
}
