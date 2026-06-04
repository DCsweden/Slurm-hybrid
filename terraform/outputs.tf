output "cluster_name" {
  value = local.cluster_name
}

output "login_ssh" {
  description = "SSH to login node"
  value       = "ssh -i <key> slurmadmin@${module.aws.login_public_ip}"
}

output "login_public_ip" {
  value = module.aws.login_public_ip
}

output "ctrl1_public_ip" {
  value = module.aws.ctrl1_public_ip
}

output "ctrl2_public_ip" {
  value = module.aws.ctrl2_public_ip
}

output "aws_compute_instance_id" {
  value = module.aws.aws_compute_instance_id
}

output "aws_compute_private_ip" {
  value = module.aws.aws_compute_private_ip
}

output "gcp_compute_instance_id" {
  value = module.gcp.compute_instance_id
}

output "gcp_compute_private_ip" {
  value = module.gcp.compute_private_ip
}

output "db_password" {
  description = "MariaDB password for slurmdbd (store in Secrets Manager)"
  value       = local.db_password
  sensitive   = true
}

output "vpn_gcp_external_ip" {
  value = module.gcp.vpn_gateway_external_ip
}

output "vpn_aws_tunnel1_address" {
  value = aws_vpn_connection.gcp.tunnel1_address
}

output "power_save_gcp_key" {
  description = "GCP service account JSON for controllers (power save)"
  value       = module.gcp.power_save_sa_key
  sensitive   = true
}

output "post_deploy_notes" {
  value = <<-EOT
    Slurm bootstrap runs automatically via GitHub Actions (job bootstrap-slurm after terraform apply).
    Manual only if workflow skipped: bash scripts/bootstrap-cluster.sh with SSH_KEY and node IPs from terraform output.
    SSH login: ssh slurmadmin@${module.aws.login_public_ip}
    Verify VPN: ping ${module.gcp.compute_private_ip} from ctrl1
  EOT
}
