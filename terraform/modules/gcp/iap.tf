resource "google_project_service" "iap" {
  project            = var.project_id
  service            = "iap.googleapis.com"
  disable_on_destroy = false
}

# IAP TCP forwarding for GitHub Actions bootstrap (primary GCP deploy path from CI).
resource "google_compute_firewall" "iap_ssh" {
  name    = "${var.project_name}-iap-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["slurm"]

  depends_on = [google_project_service.iap]
}

resource "google_project_iam_member" "ci_iap_tunnel" {
  count = var.github_ci_service_account_email != "" ? 1 : 0

  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${var.github_ci_service_account_email}"

  depends_on = [google_project_service.iap]
}

resource "google_iap_tunnel_instance_iam_member" "ci_gcp_compute" {
  count = var.github_ci_service_account_email != "" ? 1 : 0

  project  = var.project_id
  zone     = var.zone
  instance = google_compute_instance.compute.name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = "serviceAccount:${var.github_ci_service_account_email}"

  depends_on = [google_project_service.iap]
}
