# Twitties — DevOps

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-EE0000?logo=ansible&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?logo=amazonaws&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?logo=githubactions&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?logo=nodedotjs&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)

**Twitties** — a small social app (frontend + backend + database) that deploys
itself to AWS end-to-end: one `git push` to `main` provisions the
infrastructure, builds the Docker images, and rolls the new version out across
a load-balanced, auto-scaled fleet — no manual steps required.

Built with a partner as part of a university DevOps course; my primary
contributions were the Terraform infrastructure and the CI/CD pipeline.

**Live demo:** _(the URL is the frontend load balancer's DNS name, printed at
the end of each pipeline run — the app is deployed on demand rather than left
running)_

The home page shows which frontend and backend instance served your request.
Refreshing it is the quickest way to see the load balancing working.

> Twitties is the product name. The infrastructure, ECR repositories, and API
> routes still use the original `posts-app` / `posts` naming.

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

Three tiers. The two stateless tiers each run behind their own load balancer in
an auto scaling group spread across availability zones; the database is a
single instance reachable only from the backend.

```
                            Internet
                               │
                               ▼  :80
                 ┌───────────────────────────┐
                 │   Frontend ALB (public)    │
                 └───────────────────────────┘
                    │                      │      health check: GET /status
                    ▼                      ▼
            ┌──────────────┐       ┌──────────────┐
            │ Frontend EC2 │       │ Frontend EC2 │   auto scaling group
            │    :8081     │       │    :8081     │   (across AZs)
            └──────────────┘       └──────────────┘
                    │                      │
                    └──────────┬───────────┘
                               ▼  :8080
                 ┌───────────────────────────┐
                 │  Backend ALB (internal)    │   not internet-facing
                 └───────────────────────────┘
                    │                      │
                    ▼                      ▼
            ┌──────────────┐       ┌──────────────┐
            │ Backend EC2  │       │ Backend EC2  │   auto scaling group
            │    :8080     │       │    :8080     │   (across AZs)
            └──────────────┘       └──────────────┘
                    │                      │
                    └──────────┬───────────┘
                               ▼  :5432
                      ┌──────────────────┐
                      │   Database EC2   │   single instance,
                      │    PostgreSQL    │   private to the backend
                      └──────────────────┘
```

- **Frontend** — serves the UI. The only public entry point, reached through
  the frontend ALB on port `80`.
- **Backend** — the HTTP API. Its ALB is **internal**, so the API is reachable
  from the frontend tier inside the VPC but never from the internet.
- **Database** — PostgreSQL. Port `5432` is only open to the backend tier's
  security group.

Each security group only accepts traffic from the layer directly in front of
it: the frontend instances accept traffic only from the frontend ALB, the
backend ALB only from the frontend instances, the backend instances only from
the backend ALB, and the database only from the backend instances.

Every instance runs a single Docker container (via `docker compose`) pulled
from our own ECR repositories — nothing is pulled from third-party registries.
Instances authenticate to ECR using an IAM instance profile (`infra/iam.tf`),
so no registry credentials are ever stored on the servers.

### Why the load balancers matter here
- **No single point of failure.** Each stateless tier runs two or more
  instances. If one fails its health check, the ALB stops sending it traffic
  and the auto scaling group replaces it.
- **Stable addressing.** Instances are disposable and their IPs change, so
  nothing addresses an instance directly any more. The frontend finds the
  backend at the internal ALB's DNS name.
- **Zero-downtime deploys.** A new image rolls out as a rolling instance
  refresh, replacing instances a portion at a time while the rest serve
  traffic (see [section 4](#4-deploying-to-aws)).

### Request flow
1. Browser → Frontend ALB (`:80`)
2. Frontend ALB → one of the frontend instances (`:8081`)
3. Frontend → Backend ALB (`BACKEND_URL` is the internal ALB DNS name, `:8080`)
4. Backend ALB → one of the backend instances (`:8080`)
5. Backend → Database (private IP, `:5432`)
6. Response flows back the same path

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

1. **Terraform** creates the ECR repositories first, so the images built in the
   next step have somewhere to go.
2. **Docker** builds the backend, frontend, and db images and pushes them to
   ECR, tagged with the commit SHA.
3. **Terraform** applies the full infrastructure with `image_tag` pinned to
   that commit SHA (`infra/`). Because the tag is baked into each tier's launch
   template, this creates a new launch template version and triggers a
   **rolling instance refresh** on the auto scaling groups.
4. **Ansible** (`ansible/playbook.yml`) configures the database tier over SSH.
   It is the only tier Ansible touches — see below.
5. **The pipeline waits** for both rolling deployments to report success before
   the run is considered green, then prints the frontend URL.

No local Terraform apply, SSH key, IP address, or `.tfvars` file is needed —
everything runs inside the pipeline.

### How each tier is configured

| Tier | Configured by | Why |
|---|---|---|
| Frontend, Backend | Launch template user data (`infra/user_data/app_tier.sh.tftpl`) | Auto scaling group instances are created and destroyed on demand, so there is no stable host for Ansible to SSH into. Each instance installs Docker, authenticates to ECR with its instance profile, and starts its container at boot. |
| Database | Ansible over SSH | A single long-lived instance with a known address. |

### Deploying a new version

A deployment is a launch template change, not an SSH session. Terraform updates
the template, the auto scaling group replaces instances a portion at a time
(`min_healthy_percentage = 50`), and the ALB only sends traffic to instances
that pass `GET /status`. If new instances never become healthy, the refresh
fails and the pipeline fails with it.

### Required GitHub Secrets

| Secret | Purpose |
|---|---|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Credentials for the `github-actions-deploy` IAM user |
| `SDO_KEY` / `SDO_KEY_PUB` | SSH keypair GitHub Actions uses to reach the database instance |
| `DB_USER` / `DB_PASSWORD` | Database credentials |

### Terraform state
State is stored remotely in an encrypted, versioned S3 bucket
(`posts-app-terraform-state-<aws-account-id>`), created once via
`infra/bootstrap` (see `infra/bootstrap/README.md`). The
`github-actions-deploy` IAM user needs access to this bucket in addition to
its EC2, ECR, and IAM permissions.

---

## 5. Development notes

- **Why separate tiers instead of one box?** It mirrors a real production
  setup where each tier can be scaled, secured, and redeployed independently —
  and it forced us to get the security-group rules and private networking right
  (backend ↔ db) instead of everything talking over `localhost`.
- **Why Terraform + Ansible together?** Terraform is the architect — it creates
  the instances, load balancers, and network rules. Ansible is the interior
  designer for the one tier that has a fixed address: the database. The
  autoscaled tiers configure themselves at boot instead, because an instance
  that might be created at 3am by a scaling event cannot wait for someone's
  pipeline to SSH into it.
- **Why is the database not autoscaled?** An auto scaling group replaces
  instances freely, which is exactly what you want for stateless tiers and
  exactly what you do not want for the one holding your data. Managed
  multi-AZ storage (RDS) is the natural next step for this tier.
- **Why does the app show which instance served the page?** It makes the load
  balancing observable. Without it, a two-instance deployment looks identical
  to a one-instance deployment from the browser.
- **Common issues we hit:**
  - Forgetting to open a security group port after adding a new service.
  - Race conditions between instances booting and Ansible trying to SSH in
    (fixed with a wait + retry before the playbook runs).
  - `t2.micro` not being free-tier eligible in this AWS environment — fixed
    by switching to `t3.micro`.
  - Not every availability zone offers every instance type, which makes an
    auto scaling group fail to launch in that AZ. `infra/network.tf` filters
    the subnets down to AZs that actually offer the instance type.

### Known trade-offs
- Database credentials reach the backend tier through the launch template's
  user data, which puts them in Terraform state. The state bucket is encrypted
  and versioned, but a production system would keep them in AWS Secrets Manager
  or SSM Parameter Store and have instances fetch them at boot with their
  instance profile.
- The load balancers serve plain HTTP. HTTPS would need an ACM certificate and
  a domain name.

---

## 6. Appendix

Useful commands:

```bash
# Read the current infrastructure state (load balancer URLs, IPs, ECR URLs)
# without deploying
cd infra
terraform init -backend-config="bucket=posts-app-terraform-state-<account-id>" \
  -backend-config="key=posts-app/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=posts-app-terraform-locks" \
  -backend-config="encrypt=true"
terraform output

# The public URL of the app
terraform output -raw frontend_url

# Trigger a deployment manually instead of pushing to main
gh workflow run "Posts App AWS Deployment"

# Watch a rolling deployment as it happens
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name posts-app-frontend-asg \
  --query 'InstanceRefreshes[0].[Status,PercentageComplete]'

# Which instances are currently in service behind the frontend load balancer
aws elbv2 describe-target-health \
  --target-group-arn "$(aws elbv2 describe-target-groups \
    --names posts-app-frontend-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)" \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]'
```
