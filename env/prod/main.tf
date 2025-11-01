data "aws_caller_identity" "current" {}

module "iam" {
  source = "../../modules/iam"

  prefix       = local.config.prefix
  project_name = local.config.project_name
  environment  = local.config.environment
}

module "vpc" {
  source = "../../modules/vpc"

  prefix       = local.config.prefix
  project_name = local.config.project_name
  environment  = local.config.environment

  region   = local.config.region
  vpc_cidr = local.config.vpc_cidr
}

module "bastion" {
  source = "../../modules/ec2"

  prefix       = local.config.prefix
  project_name = local.config.project_name
  environment  = local.config.environment

  region    = local.config.region
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnet_ids[0]

  instance_name         = "bastion"
  instance_type         = lookup(local.config, "bastion_instance_type", "t3.medium")
  key_name              = lookup(local.config, "bastion_key_name", "ec2-kp-prod")
  instance_profile_name = module.iam.poweruser_instance_profile_name
}

module "s3" {
  source = "../../modules/s3"

  prefix       = local.config.prefix
  project_name = local.config.project_name

  enable_public_access = true
  enable_versioning    = true
  enable_hosting       = true

  index_document = "index.html"
  error_document = "error.html"

  cors_allowed_headers = ["*"]
  cors_allowed_methods = ["GET"]
  cors_allowed_origins = ["*"]
  cors_expose_headers = [
    "Date",
    "ETag",
    "x-amz-server-side-encryption",
    "x-amz-request-id",
    "x-amz-id-2",
  ]
  cors_max_age_seconds = 3600
}

module "rds" {
  source = "../../modules/rds"

  prefix       = local.config.prefix
  project_name = local.config.project_name
  environment  = local.config.environment

  name       = "app-db"
  vpc_id     = module.vpc.vpc_id
  vpc_cidr   = module.vpc.vpc_cidr
  subnet_ids = module.vpc.private_subnet_ids

  engine         = lookup(local.config, "rds_engine", "mysql")
  engine_version = lookup(local.config, "rds_engine_version", "8.0.42")
  port           = lookup(local.config, "rds_port", 3306)

  database_name   = lookup(local.config, "rds_database_name", "sigmoid_app")
  master_password = local.config.rds_master_password

  allow_ingress_from_vpc     = false
  allowed_security_group_ids = [module.bastion.security_group_id]

  backup_window          = lookup(local.config, "rds_backup_window", "02:00-04:00")
  maintenance_window     = lookup(local.config, "rds_maintenance_window", "sun:04:00-sun:05:00")
  parameter_group_family = lookup(local.config, "rds_parameter_group_family", "mysql8.0")

  cloudwatch_logs_exports      = lookup(local.config, "rds_cloudwatch_logs_exports", ["error", "slowquery", "general"])
  performance_insights_enabled = lookup(local.config, "rds_performance_insights_enabled", true)

  tags = merge(local.common_tags, { Component = "database" })
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  prefix       = local.config.prefix
  project_name = local.config.project_name
  environment  = local.config.environment

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

  prefix       = local.config.prefix
  project_name = local.config.project_name
  environment  = local.config.environment

  region     = local.config.region
  vpc_id     = module.vpc.vpc_id
  account_id = data.aws_caller_identity.current.account_id

  service_subnet_ids = module.vpc.private_subnet_ids
  alb_subnet_ids     = module.vpc.public_subnet_ids

  repository_name         = lookup(local.config, "ecs_repository_name", "sigmoid-app")
  image_tag_mutability    = lookup(local.config, "ecs_image_tag_mutability", "MUTABLE")
  keep_last_n_images      = lookup(local.config, "ecs_keep_last_n_images", 30)
  app_version             = lookup(local.config, "ecs_app_version", "1.0.2")
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  environment = local.config.environment

  static_s3_domain_name      = module.s3.asset_bucket_regional_domain_name
  api_domain_name            = module.ecs.alb_dns_name
  api_origin_protocol_policy = "http-only"
}
