# Terraform state backend bootstrap

Run this **once**, manually, with an AWS identity that has admin (or at least
`s3:CreateBucket*`/`dynamodb:CreateTable`) permissions — never from CI.

It creates:
- The S3 bucket the main pipeline uses as its Terraform state backend
  (`posts-app-terraform-state-<account-id>`), with versioning, SSE-S3
  encryption, and public access blocked.
- A DynamoDB table (`posts-app-terraform-locks`) for state locking.

## Usage

```bash
cd infra/bootstrap
terraform init
terraform apply
```

This has its own local state file (not remote — it creates the remote
backend), so keep `infra/bootstrap/terraform.tfstate` somewhere safe
(e.g. commit it to a private location or store it separately) after
applying. You should not need to run this again unless the bucket/table
are deleted.

After this succeeds, narrow the CI IAM user (`github-actions-deploy`)
down to just:
- `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` on the state bucket/prefix
- `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem` on the lock table
- No `s3:CreateBucket`, `s3:PutBucketPolicy`, `s3:PutPublicAccessBlock`,
  or `dynamodb:CreateTable` — those are admin-only, one-time actions.
