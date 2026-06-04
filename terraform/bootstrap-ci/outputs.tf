output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "aws_github_role_arn" {
  description = "GitHub Actions variable: AWS_ROLE_ARN"
  value       = aws_iam_role.github_terraform.arn
}

output "gcp_project_number" {
  value = data.google_project.current.number
}

output "gcp_service_account_email" {
  description = "GitHub Actions variable: GCP_SERVICE_ACCOUNT"
  value       = google_service_account.github_ci.email
}

output "gcp_workload_identity_provider" {
  description = "GitHub Actions variable: GCP_WORKLOAD_IDENTITY_PROVIDER (full resource name)"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_variables_setup" {
  value = <<-EOT
    Add these GitHub repository VARIABLES (Settings → Variables → Actions):

      AWS_ROLE_ARN = ${aws_iam_role.github_terraform.arn}
      GCP_WORKLOAD_IDENTITY_PROVIDER = ${google_iam_workload_identity_pool_provider.github.name}
      GCP_SERVICE_ACCOUNT = ${google_service_account.github_ci.email}
      GCP_PROJECT_ID = ${var.gcp_project_id}

    Remove obsolete secrets if present: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, GCP_SA_KEY

    Workflows require permissions: id-token: write
  EOT
}
