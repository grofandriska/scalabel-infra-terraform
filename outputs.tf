output "vpc" {
  description = "VPC összefoglaló"
  value = format("%s | %s | CIDR: %s | IGW: %s",
  var.project_name, module.vpc.vpc_id, module.vpc.vpc_cidr_block, module.vpc.internet_gateway_id)
}

output "subnets" {
  description = "Subnetek: név | típus | AZ | CIDR | ID"
  value = [
    for name, s in module.vpc.subnets :
    format("%-12s | %-7s | %-15s | %-14s | %s", name, s.type, s.az, s.cidr_block, s.id)
  ]
}

output "nat_gateways" {
  description = "NAT gatewayek"
  value = [
    for name, n in module.vpc.nat_gateways :
    format("%s | subnet: %-12s | public IP: %s", n.id, name, n.public_ip)
  ]
}

output "bastion_hosts" {
  description = "Bastion hostok: név | public IP | private IP | AZ"
  value = [
    for name, b in module.bastion.instances :
    format("%-12s | public: %-15s | private: %-12s | %s", name, b.public_ip, b.private_ip, b.az)
  ]
}

output "ec2_instances" {
  description = "Privát EC2-k: név | private IP | subnet | típus"
  value = [
    for name, i in module.ec2.instances :
    format("%-16s | private: %-12s | subnet: %-12s | %s", name, i.private_ip, i.subnet, i.instance_type)
  ]
}

output "ssh_commands" {
  description = "Kész SSH parancsok"
  value = {
    bastions = [
      for name, b in module.bastion.instances :
      format("ssh -A ec2-user@%s   # %s", b.public_ip, name)
    ]
    ec2_via_bastion = local.jump_host == null ? [] : [
      for name, i in module.ec2.instances :
      format("ssh -J ec2-user@%s ec2-user@%s   # %s", local.jump_host, i.private_ip, name)
    ]
  }
}

output "summary" {
  description = "Rövid összesítő"
  value       = <<-EOT
    Projekt:      ${var.project_name} (${var.aws_region})
    VPC:          ${module.vpc.vpc_id} (${module.vpc.vpc_cidr_block})
    Subnetek:     ${length(module.vpc.public_subnet_ids)} public, ${length(module.vpc.private_subnet_ids)} private
    NAT GW-k:     ${length(module.vpc.nat_gateways)}
    Bastionök:    ${length(module.bastion.instances)}
    EC2-k:        ${length(module.ec2.instances)}
    Kulcspár:     ${module.ec2.key_name}
  EOT
}