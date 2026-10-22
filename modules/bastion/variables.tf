variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Public subnet név => ID."
  type        = map(string)
}

variable "bastions" {
  description = "Bastion hostok listája."
  type = list(object({
    name          = string
    subnet        = string
    instance_type = optional(string)
  }))
}

variable "ami_id" {
  type = string
}

variable "default_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  description = "A használandó (EC2 modulban létrehozott) kulcspár neve."
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "Ezekről a CIDR-ekről engedélyezett az SSH."
  type        = list(string)
}
