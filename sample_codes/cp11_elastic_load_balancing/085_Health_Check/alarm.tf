# --- SNS Topic 購読 ---
resource "aws_sns_topic" "alb_alarms" {
  name = "${var.vpc_name}-alb-alarms"
}

resource "aws_sns_topic_subscription" "alb_alarms_email" {
  topic_arn = aws_sns_topic.alb_alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# --- CloudWatch アラーム: UnHealthyHostCount > 0 を検知 ---
# AWS/ApplicationELB のメトリクス。ロードバランサーとターゲットグループの両方を指定する必要があります。
resource "aws_cloudwatch_metric_alarm" "web_tg_unhealthy" {
  alarm_name          = "${var.vpc_name}-web-tg-unhealthy"
  alarm_description   = "ALB TargetGroup(web) に UnHealthy ターゲットが存在"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Minimum" # Maximum（最大値）や Average（平均値）でも同様に検知可能
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching" # データ欠損は正常扱い

  dimensions = {
    TargetGroup  = aws_lb_target_group.web.arn_suffix
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alb_alarms.arn]
  # ok_actions    = [aws_sns_topic.alb_alarms.arn] # 必要ならOKになった場合の通知も設定
}