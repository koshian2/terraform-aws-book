########################################
# EFS (両方のEC2からマウント)
########################################

# EFS用 SG（EC2 からの NFS 2049 を許可）
resource "aws_security_group" "efs" {
  name        = "${var.vpc_name}-efs-sg"
  description = "Allow NFS from SSM instances"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-efs-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_ssm" {
  security_group_id            = aws_security_group.efs.id
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = aws_security_group.ssm_instance.id
  description                  = "NFS from EC2 SSM instances"
}

resource "aws_vpc_security_group_egress_rule" "efs_all_egress" {
  security_group_id = aws_security_group.efs.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All outbound"
}

# EFS本体
resource "aws_efs_file_system" "this" {
  creation_token  = "${var.vpc_name}-efs"
  encrypted       = true
  throughput_mode = "elastic" # デフォルトのburstingからelasticに変更（推奨）

  tags = {
    Name = "${var.vpc_name}-efs"
  }
}

# 各プライベートサブネットにマウントターゲット作成（=各AZ 1つ）
resource "aws_efs_mount_target" "this" {
  for_each = {
    for idx, subnet in aws_subnet.private :
    idx => subnet
  }

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value.id
  security_groups = [aws_security_group.efs.id]
}