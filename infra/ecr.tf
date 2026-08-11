# ECR repositories for our own application images.
# These replace the lecturer-provided rmitdominichynes/sdo-2025:* images.
#
# NOTE: The CI pipeline runs `terraform destroy` + `apply` on EVERY run, scoped
# with -target flags to only the EC2/security-group resources below. This is
# deliberate: it keeps these ECR repos (and the images pushed to them) alive
# across pipeline runs. Run `terraform apply` once locally/manually (no
# -target) to create these repos the first time.

resource "aws_ecr_repository" "backend" {
  name                 = "posts-app-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "posts-app-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "db" {
  name                 = "posts-app-db"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

output "backend_ecr_repo_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "frontend_ecr_repo_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "db_ecr_repo_url" {
  value = aws_ecr_repository.db.repository_url
}
