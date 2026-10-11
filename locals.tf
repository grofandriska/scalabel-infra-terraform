locals {
  # A kulcspár a fájlból olvasott publikus kulccsal
  key_pair = {
    name       = var.key_pair.name
    public_key = file(pathexpand(var.key_pair.public_key_path))
  }

  # Kimenetekhez: az első bastion lesz az alapértelmezett jump host
  bastion_public_ips = [for b in values(module.bastion.instances) : b.public_ip]
  jump_host          = try(local.bastion_public_ips[0], null)
}