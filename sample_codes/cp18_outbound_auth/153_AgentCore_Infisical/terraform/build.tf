locals {
  artifact   = "${path.module}/../build/demo.zip"
  build_hash = filesha256(local.artifact)
}
