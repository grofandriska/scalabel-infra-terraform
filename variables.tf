variable "project_name" {
  description = "Projekt neve, minden erőforrás neve ezzel kezdődik."
  type        = string
  default     = "scalable-infra"
}

variable "aws_region" {
  description = "AWS régió."
  type        = string
  default     = "eu-central-1"
}

variable "owner" {
  description = "Az infrastruktúra tulajdonosa (név vagy e-mail), tagként kerül az erőforrásokra."
  type        = string
}

variable "vpc_config" {
  description = "VPC beállítások."
  type = object({
    cidr_block           = string
    enable_dns_hostnames = optional(bool, true)
  })

  validation {
    condition     = can(cidrnetmask(var.vpc_config.cidr_block))
    error_message = "A vpc_config.cidr_block érvényes IPv4 CIDR kell legyen (pl. 10.0.0.0/16)."
  }
}

variable "subnets" {
  description = "Subnetek listája. A 'name' egyedi kulcs, erre hivatkozik az ec2_config és a bastion_config."
  type = list(object({
    name        = string
    cidr_block  = string
    az          = string
    type        = string               # "public" vagy "private"
    nat_gateway = optional(bool, false) # csak public subneten: kerüljön-e ide NAT GW
  }))


 ## ========================================VALIDÁCIÓ========================================================
  validation {
    condition     = alltrue([for s in var.subnets : contains(["public", "private"], s.type)])
    error_message = "Minden subnet type értéke 'public' vagy 'private' lehet."
  }

  validation {
    condition     = length(distinct([for s in var.subnets : s.name])) == length(var.subnets)
    error_message = "A subnet nevek legyenek egyediek."
  }

  validation {
    condition     = alltrue([for s in var.subnets : can(cidrnetmask(s.cidr_block))])
    error_message = "Minden subnet cidr_block érvényes IPv4 CIDR kell legyen."
  }

  validation {
    condition     = alltrue([for s in var.subnets : !s.nat_gateway || s.type == "public"])
    error_message = "nat_gateway = true csak public subneten állítható be."
  }
}

variable "ec2_config" {
  description = "Subnet név => hány EC2 legyen benne (és opcionálisan milyen típusú)."
  type = map(object({
    instance_count = number
    instance_type  = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.ec2_config : v.instance_count >= 0 && floor(v.instance_count) == v.instance_count
    ])
    error_message = "Az instance_count nemnegatív egész szám kell legyen."
  }
}

variable "bastion_config" {
  description = "Bastion hostok listája. A 'subnet' egy public subnet neve."
  type = list(object({
    name          = string
    subnet        = string
    instance_type = optional(string)
  }))
  default = []

  validation {
    condition     = length(distinct([for b in var.bastion_config : b.name])) == length(var.bastion_config)
    error_message = "A bastion nevek legyenek egyediek."
  }
}

variable "key_pair" {
  description = "SSH kulcspár: AWS-beli név és a helyi publikus kulcs elérési útja."
  type = object({
    name            = string
    public_key_path = string
  })
}

variable "allowed_ssh_cidrs" {
  description = "Ezekről a címekről lehet SSH-zni a bastionökre (a saját IP-d /32-vel)."
  type        = list(string)

  validation {
    condition     = length(var.allowed_ssh_cidrs) > 0 && alltrue([for c in var.allowed_ssh_cidrs : can(cidrnetmask(c))])
    error_message = "Adj meg legalább egy érvényes CIDR-t, pl. [\"203.0.113.10/32\"]."
  }

  validation {
    condition     = !contains(var.allowed_ssh_cidrs, "0.0.0.0/0")
    error_message = "Ne nyisd meg az SSH-t az egész internetnek – használd a saját IP-det /32-vel."
  }
}

variable "default_instance_type" {
  description = "Alapértelmezett instance típus, ha nincs külön megadva."
  type        = string
  default     = "t3.micro"
}