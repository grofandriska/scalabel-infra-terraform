## Prefix for names
variable "name_prefix" {
  description = "Erőforrásnevek előtagja."
  type        = string
}

## Object for VPC tags
variable "vpc_config" {
  description = "VPC beállítások."
  type = object({
    cidr_block           = string
    enable_dns_hostnames = optional(bool, true)
  })
}

## List(Object) for subnet tags
variable "subnets" {
  description = "Subnetek listája (név, CIDR, AZ, típus, NAT GW kell-e)."
  type = list(object({
    name        = string ## Subnet Unique identifer
    cidr_block  = string
    az          = string
    type        = string                ## Private - Public
    nat_gateway = optional(bool, false) ## Makes sense olny on Public type with
  }))
}