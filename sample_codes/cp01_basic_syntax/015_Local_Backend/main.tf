terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

resource "local_file" "example" {
  content  = "サンプルのローカルファイル / Sample local file"
  filename = "${path.module}/example.txt"
}