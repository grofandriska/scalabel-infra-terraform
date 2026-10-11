variable "aws_region" {
  default = "eu-central-1"
}

variable "project_name" {
  default = "scalable-infra"
}

variable "owner" {
  default = "kovacs.peter"
}

module "vpc" {
  source = "./modules/vpc"

  name_prefix = var.project_name
  vpc_config  = { cidr_block = "10.0.0.0/16" }
  subnets = [
    { name = "public-a", cidr_block = "10.0.1.0/24", az = "eu-central-1a", type = "public", nat_gateway = true },
    ##{ name = "public-b", cidr_block = "10.0.2.0/24", az = "eu-central-1b", type = "public" },
    { name = "private-a", cidr_block = "10.0.11.0/24", az = "eu-central-1a", type = "private" },
    { name = "private-b", cidr_block = "10.0.12.0/24", az = "eu-central-1b", type = "private" },
  ]
}

output "subnets" {
  value = module.vpc.subnets
}