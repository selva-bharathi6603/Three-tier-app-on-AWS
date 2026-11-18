resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  alarms = {
    ec2-cpu-high = {
      namespace  = "AWS/EC2"
      metric     = "CPUUtilization"
      dimensions = tomap({ AutoScalingGroupName = var.asg_name })
      statistic  = "Average"
      operator   = "GreaterThanThreshold"
      threshold  = 80
    }
    alb-5xx = {
      namespace  = "AWS/ApplicationELB"
      metric     = "HTTPCode_Target_5XX_Count"
      dimensions = tomap({ LoadBalancer = var.alb_arn_suffix })
      statistic  = "Sum"
      operator   = "GreaterThanThreshold"
      threshold  = 5
    }
    alb-unhealthy-hosts = {
      namespace  = "AWS/ApplicationELB"
      metric     = "UnHealthyHostCount"
      dimensions = tomap({ LoadBalancer = var.alb_arn_suffix, TargetGroup = var.tg_arn_suffix })
      statistic  = "Maximum"
      operator   = "GreaterThanOrEqualToThreshold"
      threshold  = 1
    }
    rds-cpu-high = {
      namespace  = "AWS/RDS"
      metric     = "CPUUtilization"
      dimensions = tomap({ DBInstanceIdentifier = var.db_identifier })
      statistic  = "Average"
      operator   = "GreaterThanThreshold"
      threshold  = 80
    }
    rds-connections-high = {
      namespace  = "AWS/RDS"
      metric     = "DatabaseConnections"
      dimensions = tomap({ DBInstanceIdentifier = var.db_identifier })
      statistic  = "Average"
      operator   = "GreaterThanThreshold"
      threshold  = 60
    }
    rds-storage-low = {
      namespace  = "AWS/RDS"
      metric     = "FreeStorageSpace"
      dimensions = tomap({ DBInstanceIdentifier = var.db_identifier })
      statistic  = "Average"
      operator   = "LessThanThreshold"
      threshold  = 2147483648
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.name}-${each.key}"
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = each.value.dimensions
  statistic           = each.value.statistic
  comparison_operator = each.value.operator
  threshold           = each.value.threshold
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name}-overview"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "EC2 CPU (Auto Scaling Group)", region = var.region, stat = "Average", period = 300
          metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title = "ALB requests and 5xx", region = var.region, stat = "Sum", period = 300
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "RDS CPU", region = var.region, stat = "Average", period = 300
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_identifier]]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title   = "RDS connections", region = var.region, stat = "Average", period = 300
          metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_identifier]]
        }
      }
    ]
  })
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
