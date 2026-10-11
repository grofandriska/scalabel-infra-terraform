output "key_name" {
  value = aws_key_pair.this.key_name
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "iam_role_name" {
  value = aws_iam_role.this.name
}

output "instances" {
  description = "Instance név => részletek"
  value = {
    for k, i in aws_instance.this : k => {
      id            = i.id
      private_ip    = i.private_ip
      subnet        = local.instances[k].subnet
      az            = i.availability_zone
      instance_type = i.instance_type
    }
  }
}