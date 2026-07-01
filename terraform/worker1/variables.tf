variable "region" {
  default = "eu-central-1"
}

variable "vpc_id" {
  default = "vpc-055e63a7b37e91d70"
}

variable "master_private_ip" {
  default = "172.31.39.197"
}

variable "master_security_group_id" {
  type = string
}

variable "k3s_join_token" {
  type      = string
  sensitive = true
}