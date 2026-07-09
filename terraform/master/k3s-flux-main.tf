provider "aws" {
  region = "eu-central-1"
}

terraform {
  backend "s3" {
      bucket         = "lab-flux-k3s-terraform-state"
      key            = "master/terraform.tfstate"
      region         = "eu-central-1" 
      dynamodb_table = "terraform-state-lock" 
      encrypt        = true 
    }
}

# --- 1. RECUPERO IP PUBBLICO LOCALE ---
data "http" "mio_ip" {
  url = "http://ipv4.icanhazip.com"
}

# --- 2. GENERAZIONE CHIAVE SSH ---
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kp" {
  key_name   = "k3s-flux-key"
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename        = "${path.module}/k3s-flux-key.pem"
  content         = tls_private_key.pk.private_key_pem
  file_permission = "0600"
}

# --- 3. SECURITY GROUP ---
resource "aws_security_group" "k3s_sg" {
  name        = "k3s-flux-security-group"
  description = "Accesso EC2 K3s protetto"

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.mio_ip.response_body)}/32"]
  }

  # K8S API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.mio_ip.response_body)}/32"]
  }

  # Il Worker parla con l'API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  # Rete Flannel (Comunicazione Master <- Worker)
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  # RabbitMQ Management UI (NodePort) - Accesso riservato al tuo IP
  ingress {
    from_port   = 32002
    to_port     = 32002
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.mio_ip.response_body)}/32"]
  }
  
  # Permette a KEDA di monitorare msg rate delle queue dal Cluster DIPI
  ingress {
    from_port   = 32002
    to_port     = 32002
    protocol    = "tcp"
    cidr_blocks = ["155.185.228.200/32"]
  }

  ingress {
    description = "Consente al cluster DIPI (Vector) di leggere da RabbitMQ via AMQP"
    from_port   = 32010
    to_port     = 32010
    protocol    = "tcp"
    cidr_blocks = ["155.185.228.200/32"]
  }

  ingress {
    description = "Consente al gateway sul raspberry (Vector+Mosquitto) di scriver su RabbitMQ via AMQP"
    from_port   = 32010
    to_port     = 32010
    protocol    = "tcp"
    cidr_blocks = ["93.44.81.216/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 4. ISTANZA EC2 (FREE TIER) ---
resource "aws_instance" "k3s_server" {
  ami           = "ami-0084a47cc718c111a"
  instance_type = "t3.small"
  key_name      = aws_key_pair.kp.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  vpc_security_group_ids = [aws_security_group.k3s_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab
              echo 'vm.swappiness=10' >> /etc/sysctl.conf
              sysctl -p

              PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

              curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
                --node-name k3s-master \
                --tls-san $PUBLIC_IP \
                --write-kubeconfig-mode 644" sh -
              EOF

  lifecycle {
    ignore_changes = [user_data]
  }

  tags = {
    Name = "k3s-flux-lab"
  }
}

# --- 5. OUTPUT UTILI ---
output "Comando_ssh" {
  value = "ssh -i k3s-flux-key.pem ubuntu@${aws_instance.k3s_server.public_ip}"
}

output "Comando_kubeconfig" {
  value = "scp -i k3s-flux-key.pem ubuntu@${aws_instance.k3s_server.public_ip}:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml"
}