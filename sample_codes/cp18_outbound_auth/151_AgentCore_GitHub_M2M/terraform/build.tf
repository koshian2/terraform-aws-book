locals {
  artifact   = "${path.module}/../build/inquiry.zip"
  build_hash = filesha256(local.artifact)
}
