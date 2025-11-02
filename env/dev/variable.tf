locals {
  config     = yamldecode(file("${path.module}/../../config/dev.yaml"))
  metadata   = lookup(local.config, "metadata", {})
  aws        = lookup(local.config, "aws", {})
  networking = lookup(local.config, "networking", {})
  bastion    = lookup(local.config, "bastion", {})
  rds        = lookup(local.config, "rds", {})
  ecs        = lookup(local.config, "ecs", {})

  common_tags = merge(
    {
      Environment = lookup(local.metadata, "environment", null)
      Project     = lookup(local.metadata, "project_name", null)
      ManagedBy   = lookup(local.metadata, "managed_by", "Sigmoid")
    },
    lookup(local.config, "tags", {})
  )
}
