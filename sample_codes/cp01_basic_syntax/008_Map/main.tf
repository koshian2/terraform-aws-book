variable "pet_count_map" {
  type = map(number)
  default = {
    cat    = 2,
    dog    = 3,
    rabbit = 5
  }
}

output "pets_in_room" {
  value = [for pet, count in var.pet_count_map : "${count} ${pet}(s) are in the room."]
}