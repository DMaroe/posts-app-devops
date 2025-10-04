#!/bin/bash
set -e

echo "=== Starting Deployment ==="

# 1. Deploy infrastructure
cd infra
terraform init
terraform apply -auto-approve

# 2. Get the server IP
SERVER_IP=$(terraform output -raw app_server_public_ip)
echo "Server IP: $SERVER_IP"

# 3. Update Ansible inventory
cd ../ansible
cat > inventory.yml <<EOF
all:
  hosts:
    app_server:
      ansible_host: $SERVER_IP
      ansible_ssh_private_key_file: ~/.ssh/github_sdo_key
      ansible_user: ubuntu
EOF

# 4. Wait for instance to be ready
echo "Waiting 30 seconds for instance to boot..."
sleep 30

# 5. Run Ansible
ansible-playbook playbook.yml

echo "=== Deployment Complete ==="
echo "Frontend: http://$SERVER_IP:8081"
echo "Backend: http://$SERVER_IP:8080"