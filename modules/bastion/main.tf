# List -> map: a bastion neve a for_each kulcs
locals {
  bastions = { for b in var.bastions : b.name => b }
}

resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "Bastion: SSH only from allowed IPs"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  egress {
    description = "All outbound (SSH to private instances, updates)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-bastion-sg" }
}

resource "aws_instance" "this" {
  for_each = local.bastions

  ami                         = var.ami_id
  instance_type               = coalesce(each.value.instance_type, var.default_instance_type)
  subnet_id                   = lookup(var.public_subnet_ids, each.value.subnet, null)
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.name_prefix}-${each.key}"
    Role = "bastion"
  }

  lifecycle {
    ignore_changes = [ami]

    precondition {
      condition     = contains(keys(var.public_subnet_ids), each.value.subnet)
      error_message = "A '${each.key}' bastion subnetje ('${each.value.subnet}') nem létező vagy nem public subnet."
    }
  }
}