locals {
  artifact = "${path.module}/../build/demo.zip"
  # Hash inputs at plan time; the ZIP is only created during apply.
  build_hash = sha256(jsonencode({
    for name in ["app/server.py", "app/bootstrap.py", "scripts/build.py", "pyproject.toml", "uv.lock"] :
    name => filesha256("${path.module}/../${name}")
  }))
}

resource "terraform_data" "build" {
  triggers_replace = local.build_hash

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "uv run --frozen python scripts/build.py"
  }
}
