terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# -----------------------------
# ECR Repositories
# -----------------------------
resource "aws_ecr_repository" "webapp" {
  name         = "clo835-webapp"
  force_delete = true
}

resource "aws_ecr_repository" "mysql" {
  name         = "clo835-mysql"
  force_delete = true
}

# -----------------------------
# Default VPC + Subnet
# -----------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -----------------------------
# Amazon Linux 2 AMI
# -----------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# -----------------------------
# Security Group
# -----------------------------
resource "aws_security_group" "web_sg" {
  name   = "clo835-sg"
  vpc_id = data.aws_vpc.default.id

  # App ports
  ingress {
    from_port   = 8081
    to_port     = 8083
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# EC2 Instance
# -----------------------------
resource "aws_instance" "ec2" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = "vockey"
  associate_public_ip_address = true
  iam_instance_profile        = "LabInstanceProfile"

  tags = {
    Name = "clo835-ec2"
  }
}

# -----------------------------
# Outputs
# -----------------------------
output "ec2_public_ip" {
  value = aws_instance.ec2.public_ip
}

output "webapp_ecr_url" {
  value = aws_ecr_repository.webapp.repository_url
}

output "mysql_ecr_url" {
  value = aws_ecr_repository.mysql.repository_url
}
