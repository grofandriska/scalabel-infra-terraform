output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "subnets" {
  description = "Subnet név => részletek"
  value = {
    for k, s in aws_subnet.this : k => {
      id         = s.id
      cidr_block = s.cidr_block
      az         = s.availability_zone
      type       = local.subnets[k].type
    }
  }
}

output "subnet_ids" {
  description = "Subnet név => ID (összes)"
  value       = { for k, s in aws_subnet.this : k => s.id }
}

output "public_subnet_ids" {
  value = { for k in keys(local.public_subnets) : k => aws_subnet.this[k].id }
}

output "private_subnet_ids" {
  value = { for k in keys(local.private_subnets) : k => aws_subnet.this[k].id }
}

output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}

output "nat_gateways" {
  description = "Subnet név => NAT GW adatok"
  value = {
    for k, n in aws_nat_gateway.this : k => {
      id        = n.id
      public_ip = n.public_ip
      az        = local.nat_subnets[k].az
    }
  }
}