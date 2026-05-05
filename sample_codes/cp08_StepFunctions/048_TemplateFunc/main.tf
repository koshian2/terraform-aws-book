locals {
  train_info = templatefile("${path.module}/train_template.json.tftpl", {
    train_name   = "スーパーおおぞら / Super Ozora"
    train_number = 1
    destination  = "釧路 / Kushiro"
  })
}

output "train_data" {
  value = local.train_info
}