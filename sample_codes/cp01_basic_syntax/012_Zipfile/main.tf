# 既存の単一ファイルをZipとして圧縮（プロバイダー省略OK）
data "archive_file" "single_file_zip" {
  type        = "zip"
  source_file = "${path.module}/hello_world.py"
  output_path = "${path.module}/single_file.zip"
}

# 複数ファイルを新規作成し、サブディレクトリに入れ、Zipとして圧縮
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
  filename = "${path.module}/sample_dir/${each.key}"
  content  = each.value
}

data "archive_file" "multi_file_zip" {
  type        = "zip"
  source_dir  = "${path.module}/sample_dir"
  output_path = "${path.module}/sample_dir.zip"
  depends_on  = [local_file.example] # 暗黙的な依存関係が示せないので、depends_onで明示する
}
