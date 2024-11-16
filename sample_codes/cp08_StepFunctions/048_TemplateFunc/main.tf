locals {
  train_info = templatefile("${path.module}/train_template.json.tftpl", {
    train_name   = "スーパーおおぞら"
    train_number = 1
    destination  = "釧路"
  })
}

output "train_data" {
  value = local.train_info
}