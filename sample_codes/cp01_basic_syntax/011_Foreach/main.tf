provider "local" {}

variable "files" {
  type = map(string)
  default = {
    "example1.txt" = "Hello, this is example 1",
    "example2.txt" = "Hello, this is example 2",
    "example3.txt" = "Hello, this is example 3"
  }
}

resource "local_file" "example" {
  for_each = var.files
  filename = "${path.module}/${each.key}"
  content  = each.value
}