output "vpc_name" {
  value = google_compute_network.main.name
}

output "vpc_cidr" {
  value = var.vpc_cidr
}

output "compute_private_ip" {
  value = google_compute_instance.compute.network_interface[0].network_ip
}

output "compute_instance_id" {
  value = google_compute_instance.compute.instance_id
}

output "compute_hostname" {
  value = var.compute_hostname
}

output "vpn_gateway_external_ip" {
  value = google_compute_address.vpn.address
}

output "vpn_gateway_id" {
  value = google_compute_vpn_gateway.main.id
}

output "vpn_gateway_self_link" {
  value = google_compute_vpn_gateway.main.self_link
}

output "region" {
  value = var.region
}

output "power_save_sa_key" {
  description = "GCP SA key JSON for AWS controllers (slurm_resume/suspend)"
  value       = base64decode(google_service_account_key.slurm_power.private_key)
  sensitive   = true
}
