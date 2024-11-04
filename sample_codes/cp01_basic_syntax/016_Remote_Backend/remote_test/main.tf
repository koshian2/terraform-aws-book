terraform {
  backend "s3" {
    bucket         = "<your-remote-state-bucket>-terraform-state-bucket"  # ここにステートのバケット名を入力
    key            = "016_remote_test/terraform.tfstate"
    region         = "ap-northeast-1"                           
    dynamodb_table = "<your-remote-state-db>-terraform-locks"   # ロック用DynamoDBテーブル名を入力（オプション）
    profile        = "develop"                                  # AWS CLIのプロファイル
  }
}

resource "local_file" "example" {
  content  = "リモートファイルのテスト"
  filename = "${path.module}/example.txt"
}