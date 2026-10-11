# ---------------------------------------------------------------------------
# Flatten: { "private-a" = {instance_count=2} } ->
#   { "private-a-01" = {...}, "private-a-02" = {...} }
# Stabil kulcsok: ha 3-ról 2-re csökkented a darabszámot, csak a "-03" törlődik.
# ---------------------------------------------------------------------------
locals {
  instances = merge(concat([{}], [
    for subnet, cfg in var.instances_per_subnet : {
      for i in range(cfg.instance_count) :
      format("%s-%02d", subnet, i + 1) => {
        subnet        = subnet
        instance_type = coalesce(cfg.instance_type, var.default_instance_type)
      }
    }
  ])...)
}

# ----------------------------- Key pair ------------------------------------
resource "aws_key_pair" "this" {
  key_name   = var.key_pair.name
  public_key = var.key_pair.public_key
}

# ----------------------------- IAM (SSM hozzáférés) ------------------------
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.this.name
}

# ----------------------------- Security group ------------------------------
resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-ec2-sg"
  description = "Private EC2: SSH only from bastion, ICMP from VPC"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from bastion hosts"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = var.ssh_source_security_group_ids
  }

  ingress {
    description = "ICMP (ping) from inside the VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound (via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-ec2-sg" }
}

# ----------------------------- EC2 instance-ok -----------------------------
resource "aws_instance" "this" {
  for_each = local.instances

  ami                         = var.ami_id
  instance_type               = each.value.instance_type
  subnet_id                   = lookup(var.subnet_ids, each.value.subnet, null)
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name   = "${var.name_prefix}-${each.key}"
    Subnet = each.value.subnet
    Role   = "app"
  }

  lifecycle {
    # Új AMI kiadása ne okozzon instance-cserét minden apply-nál
    ignore_changes = [ami]

    precondition {
      condition     = contains(keys(var.subnet_ids), each.value.subnet)
      error_message = "Az ec2_config '${each.value.subnet}' subnetre hivatkozik, ami nem létezik a subnets változóban."
    }
  }
}