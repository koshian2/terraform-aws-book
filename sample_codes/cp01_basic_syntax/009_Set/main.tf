variable "pet_types" {
  type    = set(string)
  default = ["cat", "dog", "mouse", "dog"]
}

output "unique_pet_types" {
  value = [for pet in var.pet_types : "We have a ${pet}."]
}