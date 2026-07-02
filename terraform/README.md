# Terraform Infrastructure for k3s Cluster

This directory contains the Infrastructure as Code (IaC) required to provision the AWS environment for our GitOps-driven k3s cluster. 

## 1. Architecture Overview
The Terraform configuration provisions two primary EC2 instances within an AWS VPC (`eu-central-1` region):
* **k3s-master (`t3.small`)**: Runs the k3s control plane and the Kubernetes API.
* **k3s-worker (`t3.micro`)**: Runs the k3s agent and hosts application workloads.

### Security & Zero Trust Foundation
The AWS Security Groups are configured with a strict least-privilege approach:
* **Administrative Access**: SSH (port 22) and the Kubernetes API (port 6443) are restricted *exclusively* to the administrator's current public IP address (fetched dynamically during execution via `ipv4.icanhazip.com`).
* **Internal Cluster Communication**: Ports required for k3s operation (VXLAN 8472, Kubelet 10250) are strictly confined. Traffic is only allowed between the Master's and Worker's specific Security Groups, preventing any external or cross-VPC interference.
* **Instance Security**: IMDSv2 (Instance Metadata Service Version 2) is enforced requiring session tokens (`http_tokens = "required"`) to protect against SSRF attacks.

## 2. Directory Structure

### Master Node & Core Configuration
* `main.tf`: Contains the AWS provider configuration, dynamic IP fetching logic, SSH key generation, and the `k3s-master` EC2 instance definition.

### Worker Node Configuration
* `worker.tf`: Contains the dynamic AMI fetching logic and the `k3s-worker` EC2 instance definition.
* `security-group.tf`: Defines the specific ingress/egress rules for the worker node and the interlocking rules that allow the worker to communicate with the master.
* `variables.tf`: Declares the required variables (Region, VPC ID, Master Private IP, etc.) primarily used to configure the worker.
* `worker-userdata.sh.tpl`: A templated bash script injected into the worker instance. It handles swap configuration and automatically executes the k3s join command using injected variables.
* `variables.tfvars` *(Git-ignored)*: Stores sensitive runtime values like the k3s token and master security group IDs required for the worker deployment.
* `versions.tf`: Defines the required Terraform and AWS provider versions.
* `outputs.tf`: Exports useful connection strings for SSH access and `kubeconfig` retrieval.

## 3. Provisioning Workflow (Two-Phase Bootstrap)
Currently, the cluster is bootstrapped in a two-phase process to securely extract and pass the cluster join token from the master to the worker without exposing it in the state outputs.

### Phase 1: Master Node Provisioning
1. Initialize Terraform:
   ```bash
   terraform init

```

2. Apply the Master node configuration (ensuring worker variables are not yet required):
```bash
terraform apply

```


3. **Retrieve the Join Token**: Once the master is running, SSH into the instance using the generated key and retrieve the node token:
```bash
sudo cat /var/lib/rancher/k3s/server/node-token

```

### Phase 2: Worker Node Provisioning

1. Update your local `variables.tfvars` file with the parameters generated from Phase 1:
```hcl
master_security_group_id = "sg-0123456789abcdef"
master_private_ip        = "172.31.x.x"
k3s_join_token           = "K10...::server:..."

```


2. Apply the full configuration to deploy the Worker:
```bash
terraform apply

```


*Terraform reads the `worker-userdata.sh.tpl` template, injects the token and the master's IP, and automatically joins the worker to the k3s cluster.*

## 4. SSH Key Management

Terraform dynamically generates a 4096-bit RSA key pair (`tls_private_key`) during the deployment. The private keys are saved locally as `.pem` files with strict `0600` permissions.

**Security Note:**

* Do not commit the `.pem` files to version control.
* The `terraform.tfstate` file contains the private keys in plaintext. Ensure the state file is stored securely (e.g., in an encrypted S3 backend) and is strictly excluded from Git via `.gitignore`.

