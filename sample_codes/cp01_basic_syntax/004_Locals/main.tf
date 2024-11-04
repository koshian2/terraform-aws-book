locals {
  pet_name  = "dogs"
  pet_count = 5
}

output "message" {
  value = "There are ${local.pet_count} ${local.pet_name} in the room."
}