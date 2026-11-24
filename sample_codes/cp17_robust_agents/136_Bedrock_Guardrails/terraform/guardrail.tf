resource "aws_bedrock_guardrail" "guide" {
  name                      = local.name
  description               = "Denied investment advice and a fictional internal code word"
  blocked_input_messaging   = "この質問はガードレールによりブロックされました。"
  blocked_outputs_messaging = "この回答はガードレールによりブロックされました。"
  cross_region_config {
    guardrail_profile_identifier = "${local.prefix}:ap-northeast-1:${local.account}:guardrail-profile/apac.guardrail.v1:0"
  }
  topic_policy_config {
    tier_config { tier_name = "STANDARD" }
    topics_config {
      name       = "InvestmentAdvice"
      type       = "DENY"
      definition = "個別の株式や金融商品について、利益を得る目的で購入・売却・保有を勧めたり、売買の時期や投資先を具体的に提案したりする投資助言。家電の購入や製品選びは含まない。"
      examples   = ["今買うべき株式の銘柄を具体的に教えて。", "この株は今売るべきですか、それとも持ち続けるべきですか。"]
    }
  }
  word_policy_config {
    words_config { text = "PROJECT-KOHARU" }
  }
}
