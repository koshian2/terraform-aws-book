variable "pet_name" {
  type    = string
  default = "dogs"
}

variable "pet_count" {
  type    = number
  default = 5
}

output "message" {
  value = "There are ${var.pet_count} ${var.pet_name} in the room."
}