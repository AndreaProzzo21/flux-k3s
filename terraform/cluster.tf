data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- MASTER NODE ---
resource "aws_instance" "k3s_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_master
  key_name               = aws_key_pair.kp.key_name
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

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
      --token ${random_password.k3s_token.result} \
      --write-kubeconfig-mode 644" sh -
  EOF

  tags = { Name = "k3s-master" }
}

# --- WORKER NODES ---
resource "aws_instance" "k3s_worker" {
  count                  = var.worker_count # Moltiplica i nodi in base alla variabile
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_worker
  key_name               = aws_key_pair.kp.key_name
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]

  # Impone a Terraform di creare i worker solo DOPO il master
  depends_on = [aws_instance.k3s_master]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
    sysctl -p

    curl -sfL https://get.k3s.io | K3S_URL="https://${aws_instance.k3s_master.private_ip}:6443" \
    K3S_TOKEN="${random_password.k3s_token.result}" \
    INSTALL_K3S_EXEC="agent --node-name k3s-worker-${count.index + 1}" sh -
  EOF

  tags = { 
    Name = "k3s-worker-${count.index + 1}"
    Role = "agent"
  }
}
