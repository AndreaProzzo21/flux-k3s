output "Master_SSH" {
  value = "ssh -i k3s-cluster-key.pem ubuntu@${aws_instance.k3s_master.public_ip}"
}

output "Workers_SSH" {
  value = {
    for i, worker in aws_instance.k3s_worker : 
    "worker-${i + 1}" => "ssh -i k3s-cluster-key.pem ubuntu@${worker.public_ip}"
  }
}

output "Download_Kubeconfig" {
  value = "scp -i k3s-cluster-key.pem ubuntu@${aws_instance.k3s_master.public_ip}:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml"
}
