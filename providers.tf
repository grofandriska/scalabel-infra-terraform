provider "aws" {
  region = var.aws_region

  # Minden erőforrás automatikusan megkapja ezeket a tageket
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
      Owner     = var.owner
    }
  }
}
