# Posts App — DevOps

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-EE0000?logo=ansible&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?logo=amazonaws&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?logo=githubactions&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?logo=nodedotjs&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)

A Posts application (frontend + backend + database) that deploys itself to AWS
end-to-end: one `git push` to `main` provisions the infrastructure, builds the
Docker images, and configures the servers — no manual steps required.

Built with a partner as part of a university DevOps course; my primary
contributions were the Terraform infrastructure and the CI/CD pipeline.

**Live demo:** http://13.220.97.79:8081/

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Services](#2-services)
3. [Running locally with Docker Compose](#3-running-locally-with-docker-compose)
4. [Deploying to AWS](#4-deploying-to-aws)
5. [Development notes](#5-development-notes)
6. [Appendix](#6-appendix)

---

## 1. Architecture

Three services, each on its **own EC2 instance**, each with its **own
security group**:

```
                    Internet
                       │
        ┌──────────────┼──────────────┐
        │ :8081                       │ :8080
        ▼                              ▼
┌───────────────┐              ┌───────────────┐        ┌───────────────┐
│   Frontend     │  BACKEND_URL │    Backend     │  :5432 │   Database     │
│  EC2 instance  │ ───────────► │  EC2 instance  │ ─────► │  EC2 instance  │
│  (public)      │              │  (public)      │        │  (private only)│
└───────────────┘              └───────────────┘        └───────────────┘
```

- **Frontend** — serves the UI. Publicly reachable on port `8081`.
- **Backend** — exposes the Posts HTTP API. Publicly reachable on port `8080`.
- **Database** — PostgreSQL. Port `5432` is only open to the backend's
  security group, so it can never be reached directly from the internet.

Each instance runs a single Docker container (via `docker compose`) pulled
straight from our own ECR repositories — nothing is pulled from third-party
registries. EC2 instances authenticate to ECR using an IAM instance profile
(`infra/iam.tf`), so no registry credentials are ever stored on the servers.

### Request flow
1. Browser → Frontend (`:8081`)
2. Frontend → Backend (`:8080`), using the backend's public IP as `BACKEND_URL`
3. Backend → Database (private IP, `:5432`)
4. Response flows back the same path

---

## 2. Services

### Backend
Talks to the Posts DB and exposes an internal HTTP API for managing posts.

| Environment Variable | Purpose |
|---|---|
| `PORT` | Port the service listens on (default `8080`) |
| `DB_USER` | Username for connecting to the DB |
| `DB_PASSWORD` | Password for connecting to the DB |
| `DB_HOST` | Hostname/IP of the DB |

Built from `backend/Dockerfile` → pushed to `posts-app-backend` on ECR.

### Frontend
Serves the UI that lets users view and manage posts.

| Environment Variable | Purpose |
|---|---|
| `PORT` | Port the service listens on (default `8081`) |
| `BACKEND_URL` | Fully qualified URL of the backend service |

Built from `frontend/Dockerfile` → pushed to `posts-app-frontend` on ECR.

### Database
PostgreSQL with our schema migrations baked in.

| Environment Variable | Purpose |
|---|---|
| `POSTGRES_USER` | Username the backend connects with |
| `POSTGRES_PASSWORD` | Password the backend connects with |
| `POSTGRES_DB` | `posts` |

Built from `backend/DB.Dockerfile` (a thin wrapper around the official
`postgres` image with our migration SQL from `backend/migrations/` baked in)
→ pushed to `posts-app-db` on ECR.

All three images are tagged with both the commit SHA and `latest` on every
pipeline run.

---

## 3. Running locally with Docker Compose

1. Copy `.env.example` to `.env` and fill in your ECR account ID/region (or
   build the images locally and reference those tags instead).
2. `docker compose up -d` — starts all three containers (frontend, backend,
   postgres).
3. Open the app:
   - Frontend: http://localhost:8081
   - Backend:  http://localhost:8080

---

## 4. Deploying to AWS

Deployment is fully automated by the GitHub Actions pipeline
(`.github/workflows/ci-pipeline.yml`) on every push to `main`:

1. **Terraform** provisions/updates the infrastructure — 3 EC2 instances,
   their security groups, and the ECR repositories (`infra/`).
2. **Docker** builds the backend, frontend, and db images and pushes them to
   ECR.
3. **Terraform outputs** (public/private IPs of each instance) are extracted
   and used to generate an Ansible inventory on the fly.
4. **Ansible** (`ansible/playbook.yml`) SSHes into each instance, installs
   Docker, and starts the correct container with the right environment
   variables (DB credentials come from GitHub Secrets, not the repo).

No local Terraform apply, SSH key, IP address, or `.tfvars` file is needed —
everything runs inside the pipeline.

### Required GitHub Secrets

| Secret | Purpose |
|---|---|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Credentials for the `github-actions-deploy` IAM user |
| `SDO_KEY` / `SDO_KEY_PUB` | SSH keypair GitHub Actions uses to reach the EC2 instances |
| `DB_USER` / `DB_PASSWORD` | Database credentials |

### Terraform state
State is stored remotely in an encrypted, versioned S3 bucket
(`posts-app-terraform-state-<aws-account-id>`), created once via
`infra/bootstrap` (see `infra/bootstrap/README.md`). The
`github-actions-deploy` IAM user needs access to this bucket in addition to
its EC2, ECR, and IAM permissions.

---

## 5. Development notes

- **Why 3 separate EC2 instances instead of one?** It mirrors a real
  production setup where each tier can be scaled, secured, and redeployed
  independently — and it forced us to get the security-group rules and
  private networking right (backend ↔ db) instead of everything talking over
  `localhost`.
- **Why Terraform + Ansible together?** Terraform is the architect — it
  creates the instances and network rules. Ansible is the interior
  designer — it installs Docker and starts the right container on each
  box once it exists.
- **Common issues we hit:**
  - Forgetting to open a security group port after adding a new service.
  - Race conditions between instances booting and Ansible trying to SSH in
    (fixed with a wait + retry before the playbook runs).
  - `t2.micro` not being free-tier eligible in this AWS environment — fixed
    by switching to `t3.micro`.

---

## 6. Appendix

Useful commands:

```bash
# Read the current infrastructure state (IPs, ECR URLs) without deploying
cd infra
terraform init -backend-config="bucket=posts-app-terraform-state-<account-id>" \
  -backend-config="key=posts-app/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=posts-app-terraform-locks" \
  -backend-config="encrypt=true"
terraform output

# Trigger a deployment manually instead of pushing to main
gh workflow run "Posts App AWS Deployment"
```
