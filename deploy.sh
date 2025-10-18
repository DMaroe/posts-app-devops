#!/bin/bash
set -e

echo "=== Starting Deployment for Section D ==="

# 1. Deploy infrastructure
echo "Deploying infrastructure with Terraform..."
cd infra
terraform init
terraform apply -auto-approve

# 2. Extract all IPs and ALB DNS names from Terraform outputs
echo "Extracting server IPs and ALB DNS names..."
DB_PUBLIC_IP=$(terraform output -raw db_server_public_ip)
DB_PRIVATE_IP=$(terraform output -raw db_server_private_ip)

# Backend instances (array output)
BACKEND_IPS=$(terraform output -json backend_instance_ips | jq -r '.[]')
BACKEND_IP_ARRAY=($BACKEND_IPS)
BACKEND_IP_1=${BACKEND_IP_ARRAY[0]}
BACKEND_IP_2=${BACKEND_IP_ARRAY[1]}

# Frontend instances (array output)
FRONTEND_IPS=$(terraform output -json frontend_instance_ips | jq -r '.[]')
FRONTEND_IP_ARRAY=($FRONTEND_IPS)
FRONTEND_IP_1=${FRONTEND_IP_ARRAY[0]}
FRONTEND_IP_2=${FRONTEND_IP_ARRAY[1]}

# ALB DNS names
BACKEND_ALB_DNS=$(terraform output -raw backend_alb_dns)
FRONTEND_ALB_DNS=$(terraform output -raw frontend_alb_dns)

echo "Database Server - Public: $DB_PUBLIC_IP, Private: $DB_PRIVATE_IP"
echo "Backend Server 1: $BACKEND_IP_1"
echo "Backend Server 2: $BACKEND_IP_2"
echo "Backend ALB: $BACKEND_ALB_DNS"
echo "Frontend Server 1: $FRONTEND_IP_1"
echo "Frontend Server 2: $FRONTEND_IP_2"
echo "Frontend ALB: $FRONTEND_ALB_DNS"

# 3. Generate Ansible inventory dynamically
echo "Generating Ansible inventory..."
cd ../ansible
cat > inventory.yml <<EOF
all:
  children:
    database:
      hosts:
        db_server:
          ansible_host: $DB_PUBLIC_IP
          ansible_ssh_private_key_file: ~/.ssh/github_sdo_key
          ansible_user: ubuntu
    
    backend:
      hosts:
        backend_server_1:
          ansible_host: $BACKEND_IP_1
          ansible_ssh_private_key_file: ~/.ssh/github_sdo_key
          ansible_user: ubuntu
          db_private_ip: $DB_PRIVATE_IP
        backend_server_2:
          ansible_host: $BACKEND_IP_2
          ansible_ssh_private_key_file: ~/.ssh/github_sdo_key
          ansible_user: ubuntu
          db_private_ip: $DB_PRIVATE_IP
    
    frontend:
      hosts:
        frontend_server_1:
          ansible_host: $FRONTEND_IP_1
          ansible_ssh_private_key_file: ~/.ssh/github_sdo_key
          ansible_user: ubuntu
          backend_alb_dns: $BACKEND_ALB_DNS
        frontend_server_2:
          ansible_host: $FRONTEND_IP_2
          ansible_ssh_private_key_file: ~/.ssh/github_sdo_key
          ansible_user: ubuntu
          backend_alb_dns: $BACKEND_ALB_DNS
EOF

echo "Inventory generated successfully"

# 4. Wait for instances to be ready
echo "Waiting 60 seconds for all instances to boot..."
sleep 60

# 5. Run Ansible playbook
echo "Running Ansible playbook to configure all servers..."
ansible-playbook playbook.yml

echo ""
echo "=== Deployment Complete ==="
echo "========================================"
echo "Database Server: $DB_PUBLIC_IP:5432 (Private: $DB_PRIVATE_IP)"
echo "Backend Instances:"
echo "  - Backend 1: http://$BACKEND_IP_1:8080"
echo "  - Backend 2: http://$BACKEND_IP_2:8080"
echo "Backend Load Balancer: http://$BACKEND_ALB_DNS"
echo "Frontend Instances:"
echo "  - Frontend 1: http://$FRONTEND_IP_1:8081"
echo "  - Frontend 2: http://$FRONTEND_IP_2:8081"
echo "Frontend Load Balancer: http://$FRONTEND_ALB_DNS"
echo "========================================"
echo ""
echo "Access the application at: http://$FRONTEND_ALB_DNS"