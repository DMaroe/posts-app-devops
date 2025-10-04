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

# A simplified security group for our single application server
resource "aws_security_group" "app_server_sg" {
  name        = "app-server-sg"
  description = "Allow Frontend, Backend and SSH inbound traffic"

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Frontend port
  ingress {
    protocol    = "tcp"
    from_port   = 8081
    to_port     = 8081
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Backend port
  ingress {
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create the single EC2 instance
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.deployer_key.key_name
  # Use the security group we created above
  vpc_security_group_ids = [aws_security_group.app_server_sg.id]

  tags = {
    Name = "App and DB Server"
  }
}

# Output the public IP address of our server
output "app_server_public_ip" {
  value = aws_instance.app_server.public_ip
}