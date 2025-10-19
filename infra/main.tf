terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  backend "s3" {
    bucket         = "s4125640-s4125656-bucket"
    key            = "terraform.tfstate" 
    region         = "us-east-1"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

# Find the latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's owner ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get all subnets in default VPC (ALB needs at least 2 subnets)
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Create an SSH key pair to access the instances
resource "aws_key_pair" "deployer_key" {
  key_name   = "app-deployer-key"
  public_key = var.path_to_ssh_public_key
  lifecycle { 
    create_before_destroy = true 
  }
}

# ==========================================
# SECURITY GROUPS
# ==========================================

# Database Security Group - PRIVATE (no public access)
resource "aws_security_group" "db_sg" {
  name        = "database-sg"
  description = "Allow PostgreSQL from backend only"

  # Allow PostgreSQL from backend server only
  ingress {
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = [aws_security_group.backend_sg.id]
  }

  # SSH for management
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Database Security Group"
  }
}

# Backend ALB Security Group
resource "aws_security_group" "backend_alb_sg" {
  name        = "backend-alb-sg"
  description = "Allow HTTP from internet to backend ALB"

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Backend ALB Security Group"
  }
}

# Backend Instance Security Group
resource "aws_security_group" "backend_sg" {
  name        = "backend-sg"
  description = "Allow traffic from Backend ALB"

  # Allow backend port from ALB only
  ingress {
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.backend_alb_sg.id]
  }

  # SSH
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Backend Instance Security Group"
  }
}

# Frontend ALB Security Group
resource "aws_security_group" "frontend_alb_sg" {
  name        = "frontend-alb-sg"
  description = "Allow HTTP from internet to frontend ALB"

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Frontend ALB Security Group"
  }
}

# Frontend Instance Security Group
resource "aws_security_group" "frontend_sg" {
  name        = "frontend-sg"
  description = "Allow traffic from Frontend ALB"

  # Allow frontend port from ALB only
  ingress {
    protocol        = "tcp"
    from_port       = 8081
    to_port         = 8081
    security_groups = [aws_security_group.frontend_alb_sg.id]
  }

  # SSH
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Frontend Instance Security Group"
  }
}

# ==========================================
# EC2 INSTANCES
# ==========================================

# Database EC2 Instance (single instance)
resource "aws_instance" "db_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name = "Database Server"
  }
}

# Backend EC2 Instances (2 instances)
resource "aws_instance" "backend_server" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.backend_sg.id]

  tags = {
    Name = "Backend Server ${count.index + 1}"
  }
}

# Frontend EC2 Instances (2 instances)
resource "aws_instance" "frontend_server" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.frontend_sg.id]

  tags = {
    Name = "Frontend Server ${count.index + 1}"
  }
}

# ==========================================
# BACKEND APPLICATION LOAD BALANCER
# ==========================================

# Backend ALB
resource "aws_lb" "backend_alb" {
  name               = "backend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.backend_alb_sg.id]
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "Backend ALB"
  }
}

# Backend Target Group
resource "aws_lb_target_group" "backend_tg" {
  name     = "backend-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "Backend Target Group"
  }
}

# Register backend instances to target group
resource "aws_lb_target_group_attachment" "backend_attachment" {
  count            = 2
  target_group_arn = aws_lb_target_group.backend_tg.arn
  target_id        = aws_instance.backend_server[count.index].id
  port             = 8080
}

# Backend ALB Listener
resource "aws_lb_listener" "backend_listener" {
  load_balancer_arn = aws_lb.backend_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_tg.arn
  }
}

# ==========================================
# FRONTEND APPLICATION LOAD BALANCER
# ==========================================

# Frontend ALB
resource "aws_lb" "frontend_alb" {
  name               = "frontend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.frontend_alb_sg.id]
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "Frontend ALB"
  }
}

# Frontend Target Group
resource "aws_lb_target_group" "frontend_tg" {
  name     = "frontend-tg"
  port     = 8081
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "Frontend Target Group"
  }
}

# Register frontend instances to target group
resource "aws_lb_target_group_attachment" "frontend_attachment" {
  count            = 2
  target_group_arn = aws_lb_target_group.frontend_tg.arn
  target_id        = aws_instance.frontend_server[count.index].id
  port             = 8081
}

# Frontend ALB Listener
resource "aws_lb_listener" "frontend_listener" {
  load_balancer_arn = aws_lb.frontend_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
}

# ==========================================
# OUTPUTS
# ==========================================

# ALB DNS Names (what users access)
output "frontend_alb_dns" {
  value       = aws_lb.frontend_alb.dns_name
  description = "DNS name of frontend ALB - use this to access the application"
}

output "backend_alb_dns" {
  value       = aws_lb.backend_alb.dns_name
  description = "DNS name of backend ALB"
}

# Instance IPs (for Ansible to configure)
output "frontend_instance_ips" {
  value       = aws_instance.frontend_server[*].public_ip
  description = "Public IPs of frontend instances"
}

output "backend_instance_ips" {
  value       = aws_instance.backend_server[*].public_ip
  description = "Public IPs of backend instances"
}

output "db_server_public_ip" {
  value       = aws_instance.db_server.public_ip
  description = "Public IP of database server"
}

output "db_server_private_ip" {
  value       = aws_instance.db_server.private_ip
  description = "Private IP of database server"
}