# COSC2759 Assignment 2 - Semester 2, 2025

# Services


## Backend
This is the Backend Posts Service. It is responsible for talking to the Posts DB, and exposing an internal HTTP API for managing Posts.

### Environment Variables
| Environment Variable | Purpose                                                 |
|----------------------|---------------------------------------------------------|
| PORT                 | Which port will the service listen on for HTTP requests |
| DB_USER              | Username for connecting to the Backend DB               |
| DB_PASSWORD          | Password for connecting to the Backend DB               |
| DB_HOST              | Hostname/Network address for the Backend DB             |

### Image
The Backend service is built from `backend/Dockerfile` and pushed to our own ECR repository at `<account_id>.dkr.ecr.us-east-1.amazonaws.com/posts-app-backend`. The GitHub Actions pipeline builds and pushes this image automatically on every run (see `.github/workflows/ci-pipeline.yml`).

### Dependencies
The Backend service depends on a PostgreSQL database, with the required migrations. The database image is built from `backend/DB.Dockerfile` (a thin wrapper around the official `postgres` image that bakes in our migration SQL from `backend/migrations/`) and pushed to `<account_id>.dkr.ecr.us-east-1.amazonaws.com/posts-app-db`.

### Database Configuration
The PostgreSQL Databse container also requires some environment variables to be configured.

|  Environment Variable        |  Purpose                                                  |
|------------------------------|-----------------------------------------------------------|
|  POSTGRES_USER               | Username for the Backend Service to use to connect        |
|  POSTGRES_PASSWORD           | Password for the Backend Service to use to connect        |
|  POSTGRES_DB                 | "posts"                                                   |

## Frontend
This is the Frontend Posts Service. It is responsible for serving a UI to users over HTTP. This UI allows them to view and manage Posts.

### Environment Variables
| Environment Variable | Purpose                                                 |
|----------------------|---------------------------------------------------------|
| PORT                 | Which port will the service listen on for HTTP requests |
| BACKEND_URL          | Fully qualified URL for reaching the Backend Service    |

### Image
The Frontend service is built from `frontend/Dockerfile` and pushed to our own ECR repository at `<account_id>.dkr.ecr.us-east-1.amazonaws.com/posts-app-frontend`.

## Own Images (No External Dependencies)
All three services (backend, frontend, db) are built from Dockerfiles in this repository and hosted in our own AWS ECR repositories, provisioned by Terraform (`infra/ecr.tf`). We do not depend on any pre-built images from third parties. The GitHub Actions pipeline builds and pushes fresh images (tagged with the commit SHA and `latest`) before every deployment.

EC2 instances pull these images using an IAM instance profile (`infra/iam.tf`) rather than embedded credentials, so no registry secrets are stored on the servers themselves.

# Running The Services Locally (In Docker)
1. Copy `.env.example` to `.env` and fill in your ECR account ID/region (or build the images locally and reference those tags instead).
2. Run `docker compose up -d` to start all three services (frontend, backend, and a postgres database container).
3. View the Frontend Posts Service at `http://localhost:8081`, and the Backend Posts Service at `http://localhost:8080`.

# Deploying The Services

The services are deployed to AWS EC2 automatically via the GitHub Actions pipeline (`.github/workflows/ci-pipeline.yml`), which:
1. Provisions/updates the AWS infrastructure via Terraform
2. Builds and pushes the backend, frontend, and db images to ECR
3. Configures each instance and starts the correct container via Ansible

Each container needs: 
- The correct environment variables configured (refer to the above sections) — for EC2 deployments these are generated automatically by the Ansible playbook (`ansible/playbook.yml`) using values passed in from the pipeline
- Security Groups will need to be configured to allow traffic to reach the instances (already handled by `infra/main.tf`)
    - They will also need to be configured to allow the instances to talk to each other, if the services are deployed on different instances.
    - The PostgreSQL database receives inbound traffic on port `5432`
    - The ports used by the Backend and Frontend services are configurable through the `PORT` environment variable. Otherwise, it will default to port `8081`.

### Required GitHub Secrets
| Secret | Purpose |
|---|---|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Long-lived credentials for the `github-actions-deploy` IAM user |
| `SDO_KEY` / `SDO_KEY_PUB` | SSH private/public keypair used by GitHub Actions for EC2 access |
| `DB_USER` / `DB_PASSWORD` | Database credentials (no longer hardcoded in compose files) |

The workflow does not use `AWS_SESSION_TOKEN` or any local `.tfvars` file. The
Terraform public-key input is supplied from `SDO_KEY_PUB`; the private key is
used only when Ansible connects to the provisioned EC2 instances. Local
`*.tfvars` files are ignored by Git to prevent accidental commits.

### Deployment state
GitHub Actions creates an encrypted, versioned S3 bucket named
`posts-app-terraform-state-<aws-account-id>` and stores Terraform state there.
No local Terraform apply, local SSH key, local IP address, or local `.tfvars`
file is required. The `github-actions-deploy` IAM user therefore needs access
to this state bucket in addition to the EC2, ECR, and IAM permissions needed by
the Terraform configuration.

# COSC2759 Assignment 2 - Semester 2, 2025 (s4125656-s4125640)
## Extended Project Documentation

---

## 1. Project Overview
Briefly explain the purpose of the project and what it achieves.  
- Purpose of the system (e.g., managing posts through CRUD operations)

We are *automating the deployment process* of our Posts app, including its infrastructure creation so that we can avoid human errors during the deployment process.

To achieve that we need to use the given AWS environment credentials and docker images so that when our GitHub Actions workflow runs *run the deployment script* we automatically deploy the infrastructure with the application running on it.

### Section A

In section A we are required to create a README.md in which it's this file. It'll be an extension of the default README.md given by the lecturers to explain what are the components we are adding to the GitHub repository.

Then we are required to make a bash script that fully automates the deployment process, in which it's the "deploy.sh" file on the root folder. This `deploy.sh` script automates the entire deployment process for the project from infrastructure setup to application configuration. It first uses Terraform (inside the `infra` directory) to provision the necessary AWS EC2 instances for the database, backend, and frontend. After the infrastructure is created, it retrieves each server’s public and private IP addresses using Terraform outputs. Then, it dynamically generates an Ansible inventory file containing these IPs and SSH connection details so Ansible knows where and how to connect. Once the instances have had time to boot (a 45-second pause), the script runs an Ansible playbook to configure and deploy the services on the servers. Finally, it prints a summary showing all server addresses and where to access the deployed application.

Lastly, we are required to make the connection between the backend service and database container that are deployed on at least one EC2 instance. The acceptance criteria is for the Backend Container successfully connect to the Database Container. This was done through combining Terraform and Ansible. Terraform is used to setup the EC2 instances, like their security groups in which allows the Backend Container to be able to connect to the Database container and for the Backkend Container to be reached by a user through HTTP. Ansible on the other hand is used for installing the frontend/backend/database modules through docker images inside the EC2 instance. To visualize it simply, Terraform is the architect and Ansible is the interior designer.

### Section B

We are required to deploy the Frontend container as well by using the same logic as the backend and database where we use a docker image to contain the Frontend file. 

To connect Frontend and Backend we dont need to do anything specifiic, just by pulling the docker image is enough. But what we need to take a look at is the port in security group settings to allow the connection better.

### Section C

To deploy Frontend, Backend, and Database containers we install docker via Ansible 'playbook.yml'. It starts with the bash script 'deploy.sh' where it starts the Terraform to create 3 EC2 containers, then the bash script runs Ansible to pull each respective service's containers via docker. Then we have 3 EC2 instances deployed with separate instances.

GitHub actions workflow

### Section D
---

## 2. System Architecture
Describe how the services interact with each other.  
- **Architecture Diagram:**  
  *(Insert or describe a diagram showing Frontend ↔ Backend ↔ Database)*  
- **Data Flow:** Explain how requests move through the system.  
- **Ports and Communication:** Note which ports each service uses and how they connect.  

---

## 3. Development Process
Outline the development steps and workflow.  
- Setting up local development environment  
- Key challenges faced during development  
- Solutions or debugging methods you applied  
- Tools and libraries used  

## 4. Implementation Details
Provide technical explanations of each component.  
### Backend
- Routes, endpoints, and database integration  
- How environment variables are used  
- Interaction with PostgreSQL  

### Frontend
- UI layout and key pages  
- API call structure and error handling  
- Environment variable setup for BACKEND_URL  

### Database
---

## 5. Docker & Deployment Setup
Explain how you containerized and deployed the project.  
- Overview of `docker-compose.yml`  
- Steps for running locally (`docker compose up -d`)  
- Steps for deploying to EC2  
- Common issues and how you resolved them (e.g., port conflicts, missing environment variables)  

---

## 6. Challenges & Lessons Learned
Reflect on what you encountered and learned.  
- Technical or deployment challenges  
- Key takeaways about Docker, EC2, or service communication  
- Ideas for future improvements  

---

## 7. References & Resources
List any documentation, tutorials, or guides you used.  
- Official Docker / PostgreSQL / AWS documentation  
- RMIT lab or assignment references  
- Online resources or guides  

---

## 8. Appendix
Include any supporting information.  
- Example `.env` file  
- Useful Docker or deployment commands  
- Configuration notes
