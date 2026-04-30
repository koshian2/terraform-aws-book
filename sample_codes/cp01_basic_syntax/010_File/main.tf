# プロバイダーの設定 / Provider configuration
provider "local" {
}

# テキストファイルの作成 / Create a text file
resource "local_file" "example" {
  content  = "ローカルファイルのテスト / Local file test"
  filename = "${path.module}/example.txt"
}