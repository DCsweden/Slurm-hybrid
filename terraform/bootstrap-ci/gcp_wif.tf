# GitHub Actions → GCP via Workload Identity Federation (no SA JSON keys)
# https://github.com/google-github-actions/auth/blob/main/docs/README.md#workload-identity-federation

resource "google_service_account" "github_ci" {
  account_id   = var.gcp_ci_service_account_id
  display_name = "GitHub Actions Terraform (Slurm-hybrid)"
  project      = var.gcp_project_id
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "GitHub Actions"
  description               = "OIDC pool for GitHub Actions"
  project                   = var.gcp_project_id
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider_id
  display_name                       = "GitHub OIDC"
  project                            = var.gcp_project_id

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  attribute_condition = "assertion.repository == '${var.github_repository}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Allow GitHub repo to impersonate the CI service account
resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.github_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# Permissions for Terraform (GCP compute + networking in dcprod)
resource "google_project_iam_member" "github_ci_editor" {
  project = var.gcp_project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.github_ci.email}"
}

resource "google_project_iam_member" "github_ci_iam" {
  project = var.gcp_project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github_ci.email}"
}

# Required for Terraform to bind roles on project service accounts
resource "google_project_iam_member" "github_ci_project_iam" {
  project = var.gcp_project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.github_ci.email}"
}

# gcloud compute scp/ssh --tunnel-through-iap during Slurm bootstrap
resource "google_project_iam_member" "github_ci_iap_tunnel" {
  project = var.gcp_project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.github_ci.email}"
}
