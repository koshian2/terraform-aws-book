terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

resource "local_file" "example" {
  content  = "サンプルのローカルファイル"
  filename = "${path.module}/example.txt"
}