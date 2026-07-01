output "worker_ssh" {
  value = "ssh -i k3s-worker-key.pem ubuntu@${aws_instance.k3s_worker.public_ip}"
}

output "worker_private_ip" {
  value = aws_instance.k3s_worker.private_ip
}