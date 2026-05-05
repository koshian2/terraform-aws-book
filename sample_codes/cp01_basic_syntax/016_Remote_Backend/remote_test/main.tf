terraform {
  backend "s3" {
    bucket         = "<your-remote-state-bucket>-terraform-state-bucket"  # ここにステートのバケット名を入力 / Enter the state bucket name here
    key            = "016_remote_test/terraform.tfstate"
    region         = "ap-northeast-1"                           
    dynamodb_table = "<your-remote-state-db>-terraform-locks"   # ロック用DynamoDBテーブル名を入力（オプション） / Enter the DynamoDB table name for locking (optional)
    profile        = "develop"                                  # AWS CLIのプロファイル / AWS CLI profile
  }
}

resource "local_file" "example" {
  content  = "リモートファイルのテスト / Remote file test"
  filename = "${path.module}/example.txt"
}