resource "google_compute_network" "main" {
  name                    = "${var.project_name}-gcp-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "compute" {
  name          = "${var.project_name}-compute"
  ip_cidr_range = cidrsubnet(var.vpc_cidr, 8, 1)
  region        = var.region
  network       = google_compute_network.main.id
}

resource "google_compute_firewall" "slurm" {
  name    = "${var.project_name}-slurm"
  network = google_compute_network.main.name

  source_ranges = [var.vpc_cidr, var.aws_vpc_cidr]

  allow {
    protocol = "tcp"
    ports    = ["22", "6817", "6818", "6819"]
  }

  allow {
    protocol = "udp"
    ports    = ["6818"]
  }

  allow {
    protocol = "icmp"
  }

  target_tags = ["slurm"]
}

resource "google_compute_firewall" "ssh_admin" {
  name    = "${var.project_name}-ssh"
  network = google_compute_network.main.name

  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = ["slurm"]
}

# Classic VPN gateway for AWS site-to-site
resource "google_compute_address" "vpn" {
  name   = "${var.project_name}-vpn-ip"
  region = var.region
}

resource "google_compute_vpn_gateway" "main" {
  name    = "${var.project_name}-vpn-gw"
  network = google_compute_network.main.id
  region  = var.region
}

resource "google_compute_forwarding_rule" "fr_esp" {
  name        = "${var.project_name}-fr-esp"
  region      = var.region
  ip_protocol = "ESP"
  ip_address  = google_compute_address.vpn.address
  target      = google_compute_vpn_gateway.main.id
}

resource "google_compute_forwarding_rule" "fr_udp500" {
  name        = "${var.project_name}-fr-udp500"
  region      = var.region
  ip_protocol = "UDP"
  port_range  = "500"
  ip_address  = google_compute_address.vpn.address
  target      = google_compute_vpn_gateway.main.id
}

resource "google_compute_forwarding_rule" "fr_udp4500" {
  name        = "${var.project_name}-fr-udp4500"
  region      = var.region
  ip_protocol = "UDP"
  port_range  = "4500"
  ip_address  = google_compute_address.vpn.address
  target      = google_compute_vpn_gateway.main.id
}
