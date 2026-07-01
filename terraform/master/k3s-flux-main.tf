provider "aws" {
  region = "eu-central-1"
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

  # NodePort per testare le app
  ingress {
    from_port   = 30000
    to_port     = 30100
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.mio_ip.response_body)}/32"]
  }

  # Traffico HTTP per Traefik Ingress
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.mio_ip.response_body)}/32"]
  }

  # Traffico HTTPS (per il futuro con SSL)
  ingress {
    from_port   = 443
    to_port     = 443
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 4. ISTANZA EC2 (FREE TIER) ---
resource "aws_instance" "k3s_server" {
  ami           = "ami-0084a47cc718c111a" # Ubuntu 24.04 LTS (eu-central-1)
  instance_type = "t3.small"
  key_name      = aws_key_pair.kp.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  vpc_security_group_ids = [aws_security_group.k3s_sg.id]

  # SCRIPT DI BOOTSTRAP (Swap + K3s Ultra-Light)
  user_data = <<-EOF
              #!/bin/bash
              # 1. Creazione Swap (2GB) fondamentale per Flux su t3.micro
              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab
              echo 'vm.swappiness=10' >> /etc/sysctl.conf
              sysctl -p

              # 2. Installazione K3s senza fronzoli
              PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
              
              curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
                --node-name k3s-master \
                --tls-san $PUBLIC_IP \
                --write-kubeconfig-mode 644 \
                --disable traefik \
                --disable servicelb \
                --disable local-storage \
                --disable metrics-server" sh -
              EOF

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