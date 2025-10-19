# COSC2759 Assignment 2 - Semester 2, 2025 (s4125656-s4125640)
## Extended Project Documentation
**Students:** 
- Dhiwa Arya Kusumah - S4125640
- Dylan Dahran Pribadi - S4125656  


## 1. Project Overview
This project implements a fully automated deployment pipeline for a three-tier web application (Posts App) on AWS infrastructure. The solution uses Infrastructure as Code (Terraform) and Configuration Management (Ansible) to provision and configure all resources without manual intervention.

## 2. Architecture Progression

### Section B: Single Instance (Baseline)
```
Internet → EC2 Instance (Frontend:8081 → Backend:8080 → Database:5432)
```
**Purpose:** Validate automation basics and container networking

### Section C: Separated Services (Production-Ready)
```
Internet → Frontend EC2:8081 → Backend EC2:8080 → Database EC2:5432
          (Public)              (Public)             (Private IP only)
```
**Purpose:** Security isolation and GitHub Actions CI/CD

### Section D: High Availability (Enterprise-Grade)
```
Internet → Frontend ALB → [Frontend EC2 #1, Frontend EC2 #2]
               ↓
          Backend ALB → [Backend EC2 #1, Backend EC2 #2]
               ↓
          Database EC2 (Single instance)
```
**Purpose:** Load balancing, health checks, zero-downtime deployments.

## 3. Quick Start

### Prerequisites
- AWS Learner Lab credentials configured in `~/.aws/credentials`
- SSH key pair: `~/.ssh/github_sdo_key`
- Terraform, Ansible, jq installed

### Deployment steps (Local)

1. **Clone and configure:**
```bash
git clone 
cd assignment-2-s4125656-s4125640

# Fill infra/you.auto.tfvars with:
# path_to_ssh_public_key="~/.ssh/github_sdo_key.pub" 
# path_to_ssh_private_key="~/.ssh/github_sdo_key"
# my_ip_address="<Your IP address>" 
```

2. **Run deployment:**
```bash
bash deploy.sh
```

3. **Access application:**
- Section B/C: `http://<INSTANCE_IP>:8081`
- Section D: `http://<ALB_DNS>` (displayed at end of deployment)

### Deployment steps (Github Workflow)

1. Set up github secrets
```bash
AWS_ACCESS_KEY_ID         (from AWS Learner Lab)
AWS_SECRET_ACCESS_KEY     (from AWS Learner Lab)
AWS_SESSION_TOKEN         (from AWS Learner Lab)
SDO_KEY_PUB               (your public key content)
SDO_KEY                   (your private key content)
MY_IP_ADDRESS             (your public IP)
```

2. Do terraform init and terraform apply in ./bootstrap to create the S3 bucket for storing terraform state.

3. Push / pull request to main branch to run the workflow

## 4. Learning From Each Section
**Important Notes**: The learning from each section does not necessarily follow assignment progression for example the bash script is supposed to be done in Section A but we implement it later on when doing Section B

### Section A

**Challenge** : Deploy backend and database containers on a single EC2 instance and document our approach.

**What We Learned**

#### 1. Terraform basics
**Problem:** Creating AWS resources manually in the Console is error-prone and not repeatable.

**Solution:** Use Terraform to define infrastructure declaratively.
```hcl
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.app_server_sg.id]
}
```

**Why This Matters:**
- Same code produces same infrastructure every time
- Changes are version controlled in Git
- Can review infrastructure changes like code reviews

**Learning**: Creating the EC2 instance in terraform is straightforward especially after following the labs tutorial. However, we did realized that by using terraform it's really easier to think from architectural standpoint

#### 2. Security Groups
**Problem** Need to allow HTTP traffic but keep instance secure.
**Solution:** Define specific ingress/egress rules.
```hcl
resource "aws_security_group" "app_server_sg" {
  ingress {
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTP from anywhere
  }
  
  ingress {
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]  # SSH for management
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound
  }
}
```

**Learning**: Setting up the corect Inbound and Outbound rules is crucial especially when the EC2 have to be able to download the Docker Images

#### 3. Ansible
**Problem:** After Terraform creates the instance, we still need to SSH in and manually install Docker, start containers, etc.

**Solution:** Ansible playbook automates all configuration steps.
```yaml
tasks:
  - name: "Install Docker"
    apt:
      name: docker-ce
      state: present
  
  - name: "Run docker-compose"
    community.docker.docker_compose_v2:
      project_src: /home/ubuntu/app
```

**Learning**: Initially we thought that cloning the code and running the docker-compose.yml is a good idea but turns out copying the exisiting docker-compose file and send it to the EC2 instances proven to be more lightweight and faster solution.

#### 4. Docker Networking 
**Problem:** Backend container needs to talk to database container.

**Solution:** Both containers on same Docker network, backend uses container name as hostname.
```yaml
# docker-compose.yml
  backend:
    image: rmitdominichynes/sdo-2025:backend
    container_name: backend-service
    environment:
      PORT: 8080
      DB_USER: foo-user
      DB_PASSWORD: secret-foo-password
      DB_HOST: ${DB_HOST}  
    ports:
      - "8080:8080"
```

**Learning**: Docker DNS resolves container names to IPs automatically.

#### 5. Key Files created:
- `infra/main.tf` - Defines EC2 instance, security group, SSH key
- `ansible/playbook.yml` - Installs Docker, deploys containers

#### 6. Challenges Faced
1. **Missing egress rule:** Instance couldn't download Docker images - learned egress rules are essential
2. **Docker permission denied:** User needs to be in `docker` group AND SSH session reset
3. **Environment variables:** Learned to use `.env` files for container configuration
---
### Section B

#### 1. Bash Script
```bash
#!/bin/bash
# 1. Terraform creates infrastructure
terraform apply -auto-approve

# 2. Extract instance IP from Terraform
SERVER_IP=$(terraform output -raw app_server_public_ip)

# 3. Generate Ansible inventory dynamically
cat > ansible/inventory.yml <<EOF
all:
  hosts:
    app_server:
      ansible_host: $SERVER_IP
EOF

# 4. Wait for instance to boot
sleep 30

# 5. Run Ansible to configure and deploy
ansible-playbook playbook.yml
```

**Why This Script Matters:** Reduces deployment from a lot of manual steps to one command: `bash deploy.sh`

**Learning** Using environment variables, cat and echo proven very helpful during development, and also it is easier for us to fix a little problem in the ansible or terraform and just rerun the bash script.

#### 2. Terraform and Ansible
There's not a significant difference from Section it is just now we have to run the frontend container which is straightforward.

---

### Section C
**Challenge** : Deploy each service on its own EC2 instance for security isolation and implement CI/CD with GitHub Actions.

#### 1. Security Group
**Problem:** How does backend securely connect to database without exposing database to internet?

**Solution**: Referencing to a security group, example db security group to connect to backend instance
```hcl
resource "aws_security_group" "db_sg" {
  ingress {
    from_port       = 5432
    to_port         = 5432
    security_groups = [aws_security_group.backend_sg.id]  # Only backend SG!
  }
}
```

**Why This is Better:**
- Can't be bypassed.
- Works even if backend IP changes.

#### 2. Dynamic Inventory Generation
**Problem:** Each deployment creates instances with different IPs.

**Solution:** Generate Ansible inventory from Terraform outputs.
```bash
# Extract IPs from Terraform
DB_PRIVATE_IP=$(terraform output -raw db_server_private_ip)
BACKEND_PUBLIC_IP=$(terraform output -raw backend_server_public_ip)
FRONTEND_PUBLIC_IP=$(terraform output -raw frontend_server_public_ip)

# Generate inventory file
cat > ansible/inventory.yml <<EOF
all:
  children:
    database:
      hosts:
        db_server:
          ansible_host: $DB_PUBLIC_IP
    backend:
      hosts:
        backend_server:
          ansible_host: $BACKEND_PUBLIC_IP
          db_private_ip: $DB_PRIVATE_IP
EOF
```

**Learning:** Infrastructure as Code means even configuration files can be generated programmatically.

#### 3. Github Actions CI/CD 
Automate deployment on every push to `main` branch.

**Workflow Structure:**
```yaml
on:
  push:
    branches:
      - main

jobs:
  deploy:
    steps:
      - Checkout code
      - Configure AWS credentials (from GitHub Secrets)
      - Run Terraform
      - Extract outputs
      - Generate inventory
      - Run Ansible
```

**Learning**: Use github secrets to store .env 

### Challenges & Solutions of Section C
**Challenge 1: Ansible SSH Connection Timing**
- **Problem:** Ansible tries to connect before EC2 fully boots
- **Solution:** Add wait tasks in playbook
```yaml
- name: "Wait for SSH"
  wait_for_connection:
    timeout: 180
```

**Challenge 2: Docker Group Membership**
- **Problem:** Adding user to docker group doesn't take effect immediately
- **Solution:** Reset SSH connection
```yaml
- name: "Add user to docker group"
  user:
    name: ubuntu
    groups: docker
    append: yes

- name: "Reset connection"
  meta: reset_connection
```

---

### Section D
**Challenge**: Deploy multiple instances per service with Application Load Balancers for fault tolerance.

**What we Learned**

#### 1. Horizontal Scaling
**Concept:** Run 2+ instances of each service for redundancy.

**Implementation with Terraform `count`:**
```hcl
resource "aws_instance" "frontend_server" {
  count         = 2  # Creates 2 identical instances
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  
  tags = {
    Name = "Frontend Server ${count.index + 1}"
  }
}
```
**Why this matters?**: Ensure High availability even if one instance is down there's still another one.

#### 2. **Application Load Balancer (ALB)**
**Problem:** Users shouldn't connect to individual instance IPs (what if instance fails?).

**Solution:** ALB distributes traffic and health-checks instances.

**Components:**
1. **Load Balancer:** Entry point with DNS name
2. **Target Group:** Defines health check rules
3. **Targets:** The actual instances receiving traffic
4. **Listener:** Port 80 → forward to target group
```hcl
resource "aws_lb" "frontend_alb" {
  name               = "frontend-alb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids  # Must span 2+ AZs
}

resource "aws_lb_target_group" "frontend_tg" {
  port     = 8081
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 15
    interval            = 30
  }
}

resource "aws_lb_target_group_attachment" "frontend_attachment" {
  count            = 2
  target_group_arn = aws_lb_target_group.frontend_tg.arn
  target_id        = aws_instance.frontend_server[count.index].id
  port             = 8081
}
```

#### 4. ALB Listener Ports 
**Problem We Hit:** Frontend container runs on 8081, but ALB listens on port 80.

**Wrong Config:**
```yaml
# docker-compose-frontend.yml
BACKEND_URL: http://${BACKEND_HOST}:8080  
```

**Correct Config:**
```yaml
BACKEND_URL: http://${BACKEND_HOST}  # Port 80 is default for HTTP
```

**Learning:** ALB listener port (80) is not Target port (8081).

#### 5. S3 Bucket for Terraform State
**Tell Terraform to store TF State in the bucket**
```yaml
# infra/main.tf
backend "s3" {
    bucket         = "s4125640-s4125656-bucket"
    key            = "terraform.tfstate" 
    region         = "us-east-1"
    encrypt        = true

```
**Comment: with this S3 works as the remote backend to store terraform state**

**Bucket Creation:** create a bucket using terraform in ./bootstrap/main.tf
**Bucket Config:**
1. **region: us-east-1**
2. **name: s4125640-s4125656-bucket**
3. **versioning: enabled**
4. **public all access: false**

---

### Real world benefits for Yeetcode
**Without ALB (Section C):**
- Instance fails → App down until manual recovery
- Deployment → Take app offline, update, bring back up

**With ALB (Section D):**
- Instance fails → ALB auto-routes to healthy instance
- Deployment → Update one instance at a time (rolling deployment)

## Project Structure
```
assignment-2-s4125656-s4125640/
├── README.md                        
├── deploy.sh                        ← One-command deployment
│
├── infra/                           ← Terraform (Infrastructure)
│   ├── main.tf                      ← AWS resources
│   ├── variables.tf                 ← Input variables
│   └── you.auto.tfvars              ← Your values (gitignored)
│
├── ansible/                         ← Ansible (Configuration)
│   ├── ansible.cfg                  ← Ansible settings
│   ├── playbook.yml                 ← Setup tasks
│   └── inventory.yml                ← Auto-generated
│
├── docker-compose-db.yml            ← Database container
├── docker-compose-backend.yml       ← Backend container
├── docker-compose-frontend.yml      ← Frontend container
│                     
└── .github/workflows/
    └── deploy.yml                   ← CI/CD pipeline
```



