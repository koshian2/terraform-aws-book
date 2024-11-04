# プロバイダーの設定
provider "local" {
}

# テキストファイルの作成
resource "local_file" "example" {
  content  = "ローカルファイルのテスト"
  filename = "${path.module}/example.txt"
}