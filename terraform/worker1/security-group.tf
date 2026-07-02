data "http" "mio_ip" {
  url = "http://ipv4.icanhazip.com"
}

resource "aws_security_group" "k3s_worker_sg" {
  name        = "k3s-worker-security-group"
  description = "SG per il worker k3s - solo admin + traffico interno cluster"
  vpc_id      = var.vpc_id

  # SSH — solo dal tuo IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.mio_ip.response_body)}/32"]
  }

  # kubelet — solo dal master
  ingress {
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [var.master_security_group_id]
  }

  # Flannel VXLAN — solo dal master
  ingress {
    from_port       = 8472
    to_port         = 8472
    protocol        = "udp"
    security_groups = [var.master_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "k3s-worker-sg" }
}

resource "aws_security_group_rule" "master_allow_worker_api" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.k3s_worker_sg.id
  security_group_id        = var.master_security_group_id
}

resource "aws_security_group_rule" "master_allow_worker_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.k3s_worker_sg.id
  security_group_id        = var.master_security_group_id
}

resource "aws_security_group_rule" "master_allow_worker_vxlan" {
  type                     = "ingress"
  from_port                = 8472
  to_port                  = 8472
  protocol                 = "udp"
  source_security_group_id = aws_security_group.k3s_worker_sg.id
  security_group_id        = var.master_security_group_id
}