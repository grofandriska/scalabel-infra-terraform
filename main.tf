# Legfrissebb Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

module "vpc" {
  source = "./modules/vpc"

  name_prefix = var.project_name
  vpc_config  = var.vpc_config
  subnets     = var.subnets
}

module "ec2" {
  source = "./modules/ec2-instance"

  name_prefix           = var.project_name
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = module.vpc.vpc_cidr_block
  subnet_ids            = module.vpc.subnet_ids
  instances_per_subnet  = var.ec2_config
  ami_id                = data.aws_ami.al2023.id
  default_instance_type = var.default_instance_type
  key_pair              = local.key_pair

  # SSH csak a bastion security groupból engedélyezett
  ssh_source_security_group_ids = [module.bastion.security_group_id]
}

module "bastion" {
  source = "./modules/bastion"

  name_prefix           = var.project_name
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  bastions              = var.bastion_config
  ami_id                = data.aws_ami.al2023.id
  default_instance_type = var.default_instance_type
  key_name              = module.ec2.key_name
  allowed_ssh_cidrs     = var.allowed_ssh_cidrs
}