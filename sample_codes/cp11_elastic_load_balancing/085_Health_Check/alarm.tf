# --- SNS Topic 購読 --- / SNS topic subscription.
resource "aws_sns_topic" "alb_alarms" {
  name = "${var.vpc_name}-alb-alarms"
}

resource "aws_sns_topic_subscription" "alb_alarms_email" {
  topic_arn = aws_sns_topic.alb_alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# --- CloudWatch アラーム: UnHealthyHostCount > 0 を検知 --- / Detect when UnHealthyHostCount is greater than 0.
# AWS/ApplicationELB のメトリクス。ロードバランサーとターゲットグループの両方を指定する必要があります。 / AWS/ApplicationELB metrics. Both the load balancer and target group must be specified.
resource "aws_cloudwatch_metric_alarm" "web_tg_unhealthy" {
  alarm_name          = "${var.vpc_name}-web-tg-unhealthy"
  alarm_description = "ALB TargetGroup(web) に UnHealthy ターゲットが存在 / ALB TargetGroup(web) has unhealthy targets."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Minimum" # Maximum（最大値）や Average（平均値）でも同様に検知可能 / Maximum or Average can also be detected in the same way.
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching" # データ欠損は正常扱い / Treat missing data as normal

  dimensions = {
    TargetGroup  = aws_lb_target_group.web.arn_suffix
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alb_alarms.arn]
  # ok_actions    = [aws_sns_topic.alb_alarms.arn] # 必要ならOKになった場合の通知も設定 / Set this if you also need a notification when the status becomes OK.
}
