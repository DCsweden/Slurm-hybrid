#!/bin/bash
# One-time bootstrap: S3 + DynamoDB for Terraform remote state (AWS Stockholm)
set -euo pipefail

BUCKET="${1:-slurm-hybrid-tfstate}"
TABLE="${2:-slurm-hybrid-tflock}"
REGION="${3:-eu-north-1}"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket $BUCKET already exists"
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
  echo "Created bucket $BUCKET"
fi

if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" 2>/dev/null; then
  echo "Table $TABLE already exists"
else
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
  echo "Created lock table $TABLE"
fi

echo "Add GitHub secrets: TF_STATE_BUCKET=$BUCKET TF_STATE_LOCK_TABLE=$TABLE"
