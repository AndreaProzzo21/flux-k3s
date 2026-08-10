variable "region" {
  description = "Regione AWS"
  default     = "eu-central-1"
}

variable "worker_count" {
  description = "Numero di nodi worker da creare"
  type        = number
  default     = 1  # Cambia questo numero per aggiungere o rimuovere nodi
}

variable "instance_type_master" {
  default = "t3.small"
}

variable "instance_type_worker" {
  default = "t3.micro"
}
