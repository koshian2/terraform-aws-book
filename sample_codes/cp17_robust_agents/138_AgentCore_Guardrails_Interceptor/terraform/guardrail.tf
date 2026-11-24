resource "aws_bedrock_guardrail" "email" {
  name                      = "${var.name}_email"
  description               = "Anonymize EMAIL in inquiry responses; no blocking filters"
  blocked_input_messaging   = "Unable to process input."
  blocked_outputs_messaging = "Unable to process output."
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
  }
}
