# Remote state required for GitHub Actions (apply + destroy share state).
# Bucket/DynamoDB must exist in AWS Stockholm (eu-north-1) before first CI run.
# See README "GitHub Actions" for bootstrap commands.

terraform {
  backend "s3" {}
}
