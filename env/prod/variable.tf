locals {
  config = yamldecode(file("${path.module}/../../config/prod.yaml"))

  common_tags = merge(
    {
      Environment = local.config.environment
      Project     = local.config.project_name
      ManagedBy   = lookup(local.config, "managed_by", "Sigmoid")
    },
    lookup(local.config, "tags", {})
  )
}
