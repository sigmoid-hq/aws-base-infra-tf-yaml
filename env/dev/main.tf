data "aws_caller_identity" "current" {}

module "iam" {
  source = "../../modules/iam"

  prefix       = local.metadata.prefix
  project_name = local.metadata.project_name
  environment  = local.metadata.environment
}

module "vpc" {
  source = "../../modules/vpc"

  prefix       = local.metadata.prefix
  project_name = local.metadata.project_name
  environment  = local.metadata.environment

  region   = local.aws.region
  vpc_cidr = local.networking.vpc_cidr
}

module "bastion" {
  source = "../../modules/ec2"

  prefix       = local.metadata.prefix
  project_name = local.metadata.project_name
  environment  = local.metadata.environment

  region    = local.aws.region
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnet_ids[0]

  instance_name         = "bastion"
  instance_type         = lookup(local.bastion, "instance_type", "t3.small")
  key_name              = lookup(local.bastion, "key_name", "ec2-kp")
  instance_profile_name = module.iam.poweruser_instance_profile_name
}

module "s3" {
  source = "../../modules/s3"

  prefix       = local.metadata.prefix
  project_name = local.metadata.project_name

  enable_public_access = true
  enable_versioning    = true
  enable_hosting       = true

  index_document = "index.html"
  error_document = "error.html"

  cors_allowed_headers = ["*"]
  cors_allowed_methods = ["GET"]
  cors_allowed_origins = ["*"]
  cors_expose_headers  = ["Date", "ETag", "x-amz-server-side-encryption", "x-amz-request-id", "x-amz-id-2"]
  cors_max_age_seconds = 3600
}

module "rds" {
  source = "../../modules/rds"

  prefix       = local.metadata.prefix
  project_name = local.metadata.project_name
  environment  = local.metadata.environment

  name       = "app-db"
  vpc_id     = module.vpc.vpc_id
  vpc_cidr   = module.vpc.vpc_cidr
  subnet_ids = module.vpc.private_subnet_ids

  engine         = lookup(local.rds, "engine", "mysql")
  engine_version = lookup(local.rds, "engine_version", "8.0.42")
  port           = lookup(local.rds, "port", 3306)

  database_name   = lookup(local.rds, "database_name", "sigmoid_app")
  master_password = lookup(local.rds, "master_password", null)

  allow_ingress_from_vpc     = false
  allowed_security_group_ids = [module.bastion.security_group_id]

  backup_window          = lookup(local.rds, "backup_window", "03:00-04:00")
  maintenance_window     = lookup(local.rds, "maintenance_window", "sun:05:00-sun:06:00")
  parameter_group_family = lookup(local.rds, "parameter_group_family", "mysql8.0")

  cloudwatch_logs_exports      = lookup(local.rds, "cloudwatch_logs_exports", ["error", "slowquery"])
  performance_insights_enabled = lookup(local.rds, "performance_insights_enabled", false)

  tags = merge(local.common_tags, { Component = "database" })
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  prefix       = local.metadata.prefix
  project_name = local.metadata.project_name
  environment  = local.metadata.environment

  table_name   = "ddbt"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  attributes = [
    {
      name = "id"
      type = "S"
    }
  ]
}

module "ecs" {
  source = "../../modules/ecs"

  prefix       = local.metadata.prefix
  project_name = local.metadata.project_name
  environment  = local.metadata.environment

  region     = local.aws.region
  vpc_id     = module.vpc.vpc_id
  account_id = data.aws_caller_identity.current.account_id

  service_subnet_ids = module.vpc.private_subnet_ids
  alb_subnet_ids     = module.vpc.public_subnet_ids

  repository_name         = lookup(local.ecs, "repository_name", "sigmoid-app")
  image_tag_mutability    = lookup(local.ecs, "image_tag_mutability", "MUTABLE")
  keep_last_n_images      = lookup(local.ecs, "keep_last_n_images", 10)
  app_version             = lookup(local.ecs, "app_version", "1.0.2")
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  environment = local.metadata.environment

  static_s3_domain_name      = module.s3.asset_bucket_regional_domain_name
  api_domain_name            = module.ecs.alb_dns_name
  api_origin_protocol_policy = "http-only"
}
