# Recupero IP locale
data "http" "mio_ip" {
  url = "http://ipv4.icanhazip.com"
}

# Token univoco generato da Terraform per il join dei nodi
resource "random_password" "k3s_token" {
  length  = 32
  special = false
}

# Unica chiave SSH per l'intero cluster
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kp" {
  key_name   = "k3s-cluster-key"
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename        = "${path.module}/k3s-cluster-key.pem"
  content         = tls_private_key.pk.private_key_pem
  file_permission = "0600"
}

# Security Group Unificato
resource "aws_security_group" "k3s_sg" {
  name        = "k3s-cluster-sg"
  description = "SG unificato per Master e Worker"

  # Comunicazione interna al cluster (TUTTO permesso tra i nodi che hanno questo SG)
  # Risolve Flannel (8472 UDP), API interna, Kubelet (10250), ecc.
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Accesso SSH dall'esterno (tuo IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.mio_ip.response_body)}/32"]
  }

  # Accesso K8s API Server dall'esterno (tuo IP)
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.mio_ip.response_body)}/32"]
  }

  # NodePorts custom (RabbitMQ, Vector, ecc.)
  ingress {
    from_port   = 32002
    to_port     = 32002
    protocol    = "tcp"
    cidr_blocks = [
      "${chomp(data.http.mio_ip.response_body)}/32", 
      "155.185.228.200/32"
    ]
  }

  ingress {
    from_port   = 32010
    to_port     = 32010
    protocol    = "tcp"
    cidr_blocks = ["155.185.228.200/32", "93.44.81.216/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
