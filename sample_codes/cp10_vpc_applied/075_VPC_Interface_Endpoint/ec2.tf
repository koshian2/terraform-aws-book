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

# ---- EC2用セキュリティグループ（インバウンド0、全Egress許可）----
resource "aws_security_group" "ssm_instance" {
  name                   = "${var.vpc_name}-ec2-ssm-sg"
  description            = "No inbound; allow all egress for SSM over NAT"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = true
  tags = {
    Name = "${var.vpc_name}-ec2-ssm-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.ssm_instance.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All IPv4 egress (via NAT GW)"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.ssm_instance.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  description       = "All IPv6 egress (via Egress-only IGW)"
}

# ---- AMI（Amazon Linux 2023, x86_64）----
data "aws_ssm_parameter" "al2023_default_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---- EC2（各プライベートサブネットに1台ずつ）----
resource "aws_instance" "ssm" {
  count                       = length(aws_subnet.private)
  ami                         = data.aws_ssm_parameter.al2023_default_x86_64.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private[count.index].id
  vpc_security_group_ids      = [aws_security_group.ssm_instance.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.vpc_name}-ec2-ssm-${count.index + 1}"
  }
}

# 複数台のIDを出力
output "ssm_instance_ids" {
  description = "SSM-connected EC2 instance IDs (one per private subnet)"
  value       = aws_instance.ssm[*].id
}
