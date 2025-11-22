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

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "${var.vpc_name}-ec2-ssm-profile"
  role = aws_iam_role.ssm_role.name
  tags = {
    Name = "${var.vpc_name}-ec2-ssm-profile"
  }
}

# ---- EC2用セキュリティグループ（ALBからの80のみ受ける / Egressは全許可）----
resource "aws_security_group" "web_instance" {
  name                   = "${var.vpc_name}-ec2-web-sg"
  description            = "Ingress 80 from ALB SG; allow all egress (SSM/NAT)"
  vpc_id                 = module.vpc.vpc_id
  revoke_rules_on_delete = true
  tags                   = { Name = "${var.vpc_name}-ec2-web-sg" }
}

# Ingress: ALB SG → 80/TCP のみ許可（クライアント直アクセスは不可）
resource "aws_vpc_security_group_ingress_rule" "web_http_from_alb" {
  security_group_id            = aws_security_group.web_instance.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
  description                  = "Allow HTTP from ALB"
}

# Egress: 全許可 (IPv4)
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.web_instance.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All IPv4 egress (via NAT GW)"
}

# Egress: 全許可 (IPv6) ※使う場合のみ
resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.web_instance.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  description       = "All IPv6 egress (via Egress-only IGW)"
}

# ---- AMI（Ubuntu 24.04, x86_64）----
data "aws_ssm_parameter" "ubuntu_2404_default_x86_64" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  user_data = templatefile(
    "${path.module}/../../apps/flask_load_test/cloudinit.yaml.tftpl",
    {
      app_py_b64           = base64encode(file("${path.module}/../../apps/flask_load_test/app.py"))
      gunicorn_service_b64 = base64encode(file("${path.module}/../../apps/flask_load_test/gunicorn.service"))
    }
  )
}

# ---- 起動テンプレート ----
resource "aws_launch_template" "web" {
  name_prefix   = "${var.vpc_name}-lt-web-"
  image_id      = data.aws_ssm_parameter.ubuntu_2404_default_x86_64.value
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ssm_profile.name
  }

  # サブネットはASG側で指定するため、ここでは指定しない
  network_interfaces {
    # パブリックIPは付与しない（プライベートサブネット運用前提）
    associate_public_ip_address = false
    security_groups             = [aws_security_group.web_instance.id]
  }

  metadata_options {
    http_tokens = "required"
  }

  # user_data は base64 エンコード文字列
  user_data = base64encode(local.user_data)

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.vpc_name}-ec2-web"
    }
  }

  # 後続で $Latest を参照するので明示更新不要でもOK
  update_default_version = true
}

# ---- Auto Scaling Group（TGに直接ぶら下げる）----
resource "aws_autoscaling_group" "web" {
  name                = "${var.vpc_name}-asg-web"
  max_size            = 4
  min_size            = 2
  desired_capacity    = 2
  vpc_zone_identifier = module.vpc.private_subnet_ids

  health_check_type         = "ELB"
  health_check_grace_period = 300

  # ここで TG に関連付け
  target_group_arns = [aws_lb_target_group.web.arn]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  # （任意）ASGメトリクス可視化を有効化
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances",
    "GroupPendingInstances",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupTerminatingInstances",
    "GroupStandbyInstances",
  ]

  tag {
    key                 = "Name"
    value               = "${var.vpc_name}-ec2-web"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "web_cpu_target_tracking" {
  name                      = "${var.vpc_name}-asg-web-cpu-tt"
  policy_type               = "TargetTrackingScaling"
  autoscaling_group_name    = aws_autoscaling_group.web.name
  estimated_instance_warmup = 60

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value     = var.asg_target_cpu_percent
    disable_scale_in = false # スケールインを無効化したい場合は true
  }
}