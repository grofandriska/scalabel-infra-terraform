output "security_group_id" {
  value = aws_security_group.this.id
}

output "instances" {
  description = "Bastion név => részletek"
  value = {
    for k, i in aws_instance.this : k => {
      id         = i.id
      public_ip  = i.public_ip
      private_ip = i.private_ip
      subnet     = local.bastions[k].subnet
      az         = i.availability_zone
    }
  }
}