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
# Locals
# -----------------------------
locals {
  region         = "us-east-1"
  mysql_ecr_url  = aws_ecr_repository.mysql.repository_url
  webapp_ecr_url = aws_ecr_repository.webapp.repository_url
  ecr_registry   = split("/", aws_ecr_repository.mysql.repository_url)[0]
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

  ingress {
    from_port   = 8081
    to_port     = 8083
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  user_data_replace_on_change = true
  user_data                   = <<-EOF
  #!/bin/bash
  set -e
  
  log() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
  }
  
  log "1) OS update + Docker install"
  yum update -y
  yum install -y docker
  systemctl enable docker
  systemctl start docker
  usermod -aG docker ec2-user
  
  log "2) Create Docker network (if not exists)"
  docker network create clo835-net >/dev/null 2>&1 || true
  echo "Network ready: clo835-net"
  
  log "3) Write environment file: /etc/profile.d/clo835.sh"
  cat >/etc/profile.d/clo835.sh <<PROFILE
  # CLO835 environment variables
  export REGION="${local.region}"
  export ECR_REGISTRY="${local.ecr_registry}"
  export MYSQL_ECR_URL="${local.mysql_ecr_url}"
  export WEBAPP_ECR_URL="${local.webapp_ecr_url}"
  
  # Print a message ONLY when sourced in an interactive shell
  case "\$-" in
    *i*)
      echo "[clo835] Environment loaded ✅"
      echo "  REGION=\$REGION"
      echo "  ECR_REGISTRY=\$ECR_REGISTRY"
      echo "  MYSQL_ECR_URL=\$MYSQL_ECR_URL"
      echo "  WEBAPP_ECR_URL=\$WEBAPP_ECR_URL"
      ;;
  esac
  PROFILE
  chmod 644 /etc/profile.d/clo835.sh
  
  log "4) Create helper command: /usr/local/bin/ecr-sync"
  cat >/usr/local/bin/ecr-sync <<'SCRIPT'
  #!/bin/bash
  set -e
  
  section() {
    echo
    echo "-------------------- $1 --------------------"
  }
  
  # Load env vars
  [ -f /etc/profile.d/clo835.sh ] && source /etc/profile.d/clo835.sh
  
  : "$${REGION:?REGION not set}"
  : "$${ECR_REGISTRY:?ECR_REGISTRY not set}"
  : "$${MYSQL_ECR_URL:?MYSQL_ECR_URL not set}"
  : "$${WEBAPP_ECR_URL:?WEBAPP_ECR_URL not set}"
  
  MYSQL_IMAGE="$${MYSQL_ECR_URL}:latest"
  WEBAPP_IMAGE="$${WEBAPP_ECR_URL}:latest"
  
  section "Logging in to ECR"
  aws ecr get-login-password --region "$${REGION}" \
    | docker login --username AWS --password-stdin "$${ECR_REGISTRY}"
  echo "✅ Logged in to: $${ECR_REGISTRY}"
  
  section "Pulling images"
  echo "→ Pulling MySQL:  $${MYSQL_IMAGE}"
  docker pull "$${MYSQL_IMAGE}"
  echo
  echo "→ Pulling WebApp: $${WEBAPP_IMAGE}"
  docker pull "$${WEBAPP_IMAGE}"
  
  section "Done"
  SCRIPT
  chmod +x /usr/local/bin/ecr-sync

  log "5) Completed userdata setup"
  echo "Tip: run 'source /etc/profile.d/clo835.sh' then run 'ecr-sync'"
  EOF

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
