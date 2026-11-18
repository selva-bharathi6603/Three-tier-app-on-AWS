output "website_url" {
  value = "https://${module.frontend.cloudfront_domain}"
}

output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "db_endpoint" {
  value = module.database.address
}

output "db_secret_arn" {
  value = module.database.secret_arn
}
