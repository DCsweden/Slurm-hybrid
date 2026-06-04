data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

resource "google_compute_instance" "compute" {
  name         = var.compute_hostname
  machine_type = var.instance_type_compute
  zone         = var.zone

  tags = ["slurm", "compute", "gcp"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = 80
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.compute.id
    network_ip = var.compute_private_ip
  }

  metadata = {
    ssh-keys = "slurmadmin:${var.ssh_public_key}"
  }

  metadata_startup_script = templatefile("${path.module}/startup-compute.sh.tpl", {
    slurm_version      = var.slurm_version
    node_name          = var.compute_hostname
    cloud_provider     = "gcp"
    slurm_conf         = local.slurm_conf
    install_script     = local.install_script
    bootstrap_compute  = local.bootstrap_compute
    instance_name      = var.compute_hostname
    zone               = var.zone
  })

  service_account {
    email  = google_service_account.compute.email
    scopes = ["cloud-platform"]
  }

  labels = {
    slurm_cluster = var.cluster_name
    role          = "compute"
    cloud         = "gcp"
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }
}

resource "google_service_account" "compute" {
  account_id   = substr("${var.project_name}-gcp-compute", 0, 30)
  display_name = "Slurm GCP compute node"
}

resource "google_project_iam_member" "compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.compute.email}"
}

# Controller SA for power save (start/stop this VM)
resource "google_service_account" "slurm_power" {
  account_id   = substr("${var.project_name}-slurm-ps", 0, 30)
  display_name = "Slurm power save (used on AWS controllers)"
}

resource "google_project_iam_member" "power_save" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.slurm_power.email}"
}

resource "google_service_account_key" "slurm_power" {
  service_account_id = google_service_account.slurm_power.name
}
