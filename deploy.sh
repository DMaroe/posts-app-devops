#!/bin/bash
set -e

echo "=== Starting Deployment for Section C ==="

# 1. Deploy infrastructure
echo "Deploying infrastructure with Terraform..."
cd infra
terraform init
terraform apply -auto-approve

# 2. Extract all IPs from Terraform outputs
echo "Extracting server IPs..."
DB_PUBLIC_IP=$(terraform output -raw db_server_public_ip)
DB_PRIVATE_IP=$(terraform output -raw db_server_private_ip)
BACKEND_PUBLIC_IP=$(terraform output -raw backend_server_public_ip)
BACKEND_PRIVATE_IP=$(terraform output -raw backend_server_private_ip)
FRONTEND_PUBLIC_IP=$(terraform output -raw frontend_server_public_ip)

echo "Database Server - Public: $DB_PUBLIC_IP, Private: $DB_PRIVATE_IP"
echo "Backend Server - Public: $BACKEND_PUBLIC_IP, Private: $BACKEND_PRIVATE_IP"
echo "Frontend Server - Public: $FRONTEND_PUBLIC_IP"

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
        backend_server:
          ansible_host: $BACKEND_PUBLIC_IP
          ansible_ssh_private_key_file: ~/.ssh/github_sdo_key
          ansible_user: ubuntu
          db_private_ip: $DB_PRIVATE_IP
    
    frontend:
      hosts:
        frontend_server:
          ansible_host: $FRONTEND_PUBLIC_IP
          ansible_ssh_private_key_file: ~/.ssh/github_sdo_key
          ansible_user: ubuntu
          backend_public_ip: $BACKEND_PUBLIC_IP
EOF

echo "Inventory generated successfully"

# 4. Wait for instances to be ready
echo "Waiting 45 seconds for all instances to boot..."
sleep 45

# 5. Run Ansible playbook
echo "Running Ansible playbook to configure all servers..."
ansible-playbook playbook.yml

echo ""
echo "=== Deployment Complete ==="
echo "================================"
echo "Database Server: $DB_PUBLIC_IP:5432 (Private: $DB_PRIVATE_IP)"
echo "Backend Server:  http://$BACKEND_PUBLIC_IP:8080"
echo "Frontend Server: http://$FRONTEND_PUBLIC_IP:8081"
echo "================================"
echo ""
echo "Test the application at: http://$FRONTEND_PUBLIC_IP:8081"