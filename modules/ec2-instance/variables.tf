variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  description = "A VPC CIDR-je (ICMP/ping engedélyezéséhez a VPC-n belül)."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet név => subnet ID (a VPC modul kimenete)."
  type        = map(string)
}

variable "instances_per_subnet" {
  description = <<-EOT
    A "komplex változó": subnet név => hány instance (és opcionálisan típus).
    Példa: { "private-a" = { instance_count = 2 }, "private-b" = { instance_count = 1, instance_type = "t3.small" } }
  EOT
  type = map(object({
    instance_count = number
    instance_type  = optional(string)
  }))
}

variable "ami_id" {
  type = string
}

variable "default_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_pair" {
  description = "Létrehozandó kulcspár neve és publikus kulcsa."
  type = object({
    name       = string
    public_key = string
  })
}

variable "ssh_source_security_group_ids" {
  description = "Ezekből a security groupokból jöhet SSH (a bastion SG)."
  type        = list(string)
}