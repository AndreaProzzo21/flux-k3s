data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

terraform {
  backend "s3" {
      bucket         = "lab-flux-k3s-terraform-state"
      key            = "worker/terraform.tfstate"
      region         = "eu-central-1" 
      dynamodb_table = "terraform-state-lock" 
      encrypt        = true 
    }
}

resource "tls_private_key" "worker_pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "worker_kp" {
  key_name   = "k3s-worker-key"
  public_key = tls_private_key.worker_pk.public_key_openssh
}

resource "local_file" "worker_ssh_key" {
  filename        = "${path.module}/k3s-worker-key.pem"
  content         = tls_private_key.worker_pk.private_key_pem
  file_permission = "0600"
}

resource "aws_instance" "k3s_worker" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.worker_kp.key_name

  vpc_security_group_ids = [aws_security_group.k3s_worker_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = templatefile("${path.module}/worker-userdata.sh.tpl", {
    master_private_ip = var.master_private_ip
    k3s_token          = var.k3s_join_token
  })

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "k3s-worker"
    Role = "agent"
  }
}