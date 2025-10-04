terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
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



# Create an SSH key pair to access the instance
resource "aws_key_pair" "deployer_key" {
  key_name   = "app-deployer-key"
  public_key = file(var.path_to_ssh_public_key)
}

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
}

# Backend Security Group
resource "aws_security_group" "backend_sg" {
  name        = "backend-sg"
  description = "Allow HTTP from frontend and public"

  # Allow backend port from anywhere (public API)
  ingress {
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = ["0.0.0.0/0"]
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
}

# Frontend Security Group
resource "aws_security_group" "frontend_sg" {
  name        = "frontend-sg"
  description = "Allow HTTP from public"

  # Allow frontend port from anywhere
  ingress {
    protocol    = "tcp"
    from_port   = 8081
    to_port     = 8081
    cidr_blocks = ["0.0.0.0/0"]
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
}

# Database EC2 Instance
resource "aws_instance" "db_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name = "Database Server"
  }
}

# Backend EC2 Instance
resource "aws_instance" "backend_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.backend_sg.id]

  tags = {
    Name = "Backend Server"
  }
}

# Frontend EC2 Instance
resource "aws_instance" "frontend_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.frontend_sg.id]

  tags = {
    Name = "Frontend Server"
  }
}

output "db_server_public_ip" {
  value = aws_instance.db_server.public_ip
}

output "db_server_private_ip" {
  value = aws_instance.db_server.private_ip
}

output "backend_server_public_ip" {
  value = aws_instance.backend_server.public_ip
}

output "backend_server_private_ip" {
  value = aws_instance.backend_server.private_ip
}

output "frontend_server_public_ip" {
  value = aws_instance.frontend_server.public_ip
}