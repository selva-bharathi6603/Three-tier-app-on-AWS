locals {
  name = "${var.project}-${var.environment}"
}

module "network" {
  source   = "./modules/network"
  name     = local.name
  vpc_cidr = var.vpc_cidr
  az_count = 2
}

module "database" {
  source             = "./modules/database"
  name               = local.name
  database_subnet_id = module.network.database_subnet_ids
  db_sg_id           = module.network.db_sg_id
  instance_class     = var.db_instance_class
}

module "compute" {
  source             = "./modules/compute"
  name               = local.name
  region             = var.region
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  alb_sg_id          = module.network.alb_sg_id
  app_sg_id          = module.network.app_sg_id
  instance_type      = var.instance_type
  db_host            = module.database.address
  db_port            = module.database.port
  db_name            = module.database.db_name
  db_secret_arn      = module.database.secret_arn
  app_source         = file("${path.root}/../app/app.py")
  app_requirements   = file("${path.root}/../app/requirements.txt")
}

module "frontend" {
  source        = "./modules/frontend"
  name          = local.name
  alb_dns_name  = module.compute.alb_dns_name
  frontend_file = "${path.root}/../frontend/index.html"
}

module "monitoring" {
  source             = "./modules/monitoring"
  name               = local.name
  region             = var.region
  alert_email        = var.alert_email
  monthly_budget_usd = var.monthly_budget_usd
  asg_name           = module.compute.asg_name
  alb_arn_suffix     = module.compute.alb_arn_suffix
  tg_arn_suffix      = module.compute.target_group_arn_suffix
  db_identifier      = module.database.identifier
}
