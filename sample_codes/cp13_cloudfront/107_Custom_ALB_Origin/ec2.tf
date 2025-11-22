# ---- SSM用 IAMロール & インスタンスプロフィール ----
resource "aws_iam_role" "ssm_role" {
  name = "${var.vpc_name}-ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = {
    Name = "${var.vpc_name}-ec2-ssm-role"
  }
}

# EC2 ロールに S3 読み取り権限を付与
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "s3_read_app" {
  name        = "${var.vpc_name}-s3-read-gradio-app"
  description = "Allow GetObject for app artifacts"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:GetObject"],
      Resource = "arn:aws:s3:::${local.app_bucket_name}/${local.app_prefix}/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_read_app" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = aws_iam_policy.s3_read_app.arn
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "${var.vpc_name}-ec2-ssm-profile"
  role = aws_iam_role.ssm_role.name
  tags = {
    Name = "${var.vpc_name}-ec2-ssm-profile"
  }
}

# ---- EC2用セキュリティグループ（全Egress許可）----
resource "aws_security_group" "web_instance" {
  name                   = "${var.vpc_name}-ec2-web-sg"
  description            = "No inbound; allow all egress for SSM over NAT"
  vpc_id                 = module.vpc.vpc_id
  revoke_rules_on_delete = true
  tags = {
    Name = "${var.vpc_name}-ec2-web-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.web_instance.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All IPv4 egress (via NAT GW)"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.web_instance.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  description       = "All IPv6 egress (via Egress-only IGW)"
}

# ---- AMI（Ubuntu 24.04, x86_64）----
data "aws_ssm_parameter" "ubuntu_2404_default_x86_64" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# ---- 起動テンプレート ----
data "aws_region" "current" {}

resource "aws_launch_template" "web" {
  name_prefix   = "${var.vpc_name}-lt-web-"
  image_id      = data.aws_ssm_parameter.ubuntu_2404_default_x86_64.value
  instance_type = "t3.micro"

  iam_instance_profile { name = aws_iam_instance_profile.ssm_profile.name }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.web_instance.id]
  }

  metadata_options { http_tokens = "required" }

  user_data = base64encode(
    templatefile("${path.module}/../../apps/gradio_image_classification/user_data_gradio_s3.yaml.tftpl", {
      bucket = aws_s3_bucket.app.bucket
      prefix = local.app_prefix
      region = data.aws_region.current.region
    })
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.vpc_name}-ec2-web" }
  }

  update_default_version = true
}

# ---- Auto Scaling Group（2台起動 / 配置は private_subnet_ids から）----
resource "aws_autoscaling_group" "web" {
  name                      = "${var.vpc_name}-asg-web"
  max_size                  = 2
  min_size                  = 2
  desired_capacity          = 2
  vpc_zone_identifier       = module.vpc.private_subnet_ids
  health_check_type         = "ELB" # ← TG/ALBヘルスチェックを使う
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.web.arn]

  tag {
    key                 = "Name"
    value               = "${var.vpc_name}-ec2-web"
    propagate_at_launch = true
  }

  lifecycle { create_before_destroy = true }
}
