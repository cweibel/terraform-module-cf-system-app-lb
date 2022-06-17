variable subnet_ids            {}  # The AWS Subnet Id to place the lb into
variable resource_tags         {}  # AWS tags to apply to resources
variable vpc_id                {}  # The VPC Id
variable apps_domain           {}  # url used for apps domain
variable system_domain         {}  # url used for system domain
variable route53_zone_id       {}  # Route53 zone id
variable security_groups       {}  # Array of security groups to use
variable apps_acm_arn          {}  # ACM arn for the apps certificates
variable system_acm_arn        {}  # ACM arn for the system certificates
variable internal_lb           { default = true } # Determine whether the load balancer is internal-only facing

variable enable_route_53       { default = 1 }  # Disable if using CloudFlare or other DNS




#################################################################################
# ALB
#################################################################################
resource "aws_lb" "cf_system_app_alb" {
  name               = "cf-system-apps-alb"
  internal           = var.internal_lb
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = var.security_groups
  tags = merge({Name = "cf-system-apps-alb"}, var.resource_tags)
}

#################################################################################
# ALB Target Group
#################################################################################
resource "aws_lb_target_group" "cf_system_app_alb_tg" {
  name     = "cf-system-apps-alb-tg"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = var.vpc_id
  tags     = merge({Name = "cf-system-apps-alb-tg"}, var.resource_tags)
  health_check {
    path = "/health"
    port = 8080
    protocol = "HTTP"
  }
}

#################################################################################
# ALB Target Group Attachment - Removed, should be done with vm_extension
#################################################################################
# data "aws_instances" "cf_router_instances" {
#   instance_tags = {
#     instance_group = "router"
#   }
# }
# resource "aws_lb_target_group_attachment" "cf_system_app_alb_tga" {
#   count            = length(data.aws_instances.cf_router_instances.ids)
#   target_id        = data.aws_instances.cf_router_instances.ids[count.index]
#   target_group_arn = aws_lb_target_group.cf_system_app_alb_tg.arn
#   port             = 443
# }

################################################################################
# ALB Listener - System Domain
################################################################################
resource "aws_alb_listener" "cf_system_app_alb_listener" {
  load_balancer_arn = aws_lb.cf_system_app_alb.arn
  port = "443"
  protocol = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn = var.apps_acm_arn
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.cf_system_app_alb_tg.arn
  }
  tags = merge({Name = "cf-system-apps-alb-listener-sys"}, var.resource_tags)
}


################################################################################
# ALB Listener Certificate - Apps Domain
# For future self - this is how you map a second domain to a listener
################################################################################
resource "aws_alb_listener_certificate" "alb_listner_apps_crt" {
  listener_arn    = aws_alb_listener.cf_system_app_alb_listener.arn
  certificate_arn = var.system_acm_arn
}


################################################################################
# CF ALB Route53 DNS CNAME Record - System Domain
################################################################################
resource "aws_route53_record" "cf_system_app_alb_record_sys" {
  count   = var.enable_route_53
  zone_id = var.route53_zone_id
  name    = var.system_domain
  type    = "CNAME"
  ttl     = "60"
  records = ["${aws_lb.cf_system_app_alb.dns_name}"]
}

################################################################################
# CF ALB Route53 DNS CNAME Record - Apps Domain
################################################################################
resource "aws_route53_record" "cf_system_app_alb_record_apps" {
  count   = var.enable_route_53
  zone_id = var.route53_zone_id
  name    = var.apps_domain
  type    = "CNAME"
  ttl     = "60"
  records = ["${aws_lb.cf_system_app_alb.dns_name}"]
}


output "dns_name" {value = aws_lb.cf_system_app_alb.dns_name}
output "lb_name"  {value = aws_lb.cf_system_app_alb.name }


