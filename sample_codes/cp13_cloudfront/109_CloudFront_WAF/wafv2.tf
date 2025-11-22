#---------------------------------------
# CloudFront 用 WAFv2 Web ACL（Bot 対策メイン）
#---------------------------------------
resource "aws_wafv2_web_acl" "cloudfront_waf" {
  provider = aws.us_east_1

  name        = "${var.vpc_name}-cloudfront-waf"
  description = "WAF for CloudFront distribution basic bot protection"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # --- ルール定義 ---
  rule {
    name     = "AWS-AWSManagedRulesBotControlRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.vpc_name}-bot-control"
      sampled_requests_enabled   = true
    }
  }

  # ついでに一般的な悪質リクエストも防ぎたい場合（任意）
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # ファイルアップロード時のエラー対策
        # SizeRestrictions_BODY を Count にしてブロックしない（実質除外）
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {} # or allow {} にすると「そのルールがマッチしたら即 allow」
          }
        }

        rule_action_override {
          name = "CrossSiteScripting_BODY"
          action_to_use {
            count {} # XSS攻撃のリスクはない上で除外する
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.vpc_name}-common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.vpc_name}-cloudfront-waf"
    sampled_requests_enabled   = true
  }
}
