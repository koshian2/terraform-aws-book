# ---- VPCの定義 ---- / VPC definitions
# VPC Aの定義 / Definition of VPC A
module "vpc_a" {
  source = "../../../modules/vpc"

  vpc_cidr_block     = var.vpc_a_cidr_block
  vpc_name           = var.vpc_a_name
  availability_zones = var.availability_zones
}

# VPC Bの定義 / Definition of VPC B
module "vpc_b" {
  source = "../../../modules/vpc"

  vpc_cidr_block     = var.vpc_b_cidr_block
  vpc_name           = var.vpc_b_name
  availability_zones = var.availability_zones
}

## VPC Lattice: Service Network + VPC 関連付け / VPC Lattice: Service Network + VPC association
# ---- VPC Lattice: Service Network ----
resource "aws_vpclattice_service_network" "sn" {
  name = "${var.vpc_a_name}-${var.vpc_b_name}-sn"
  # 認証不要で相互アクセス（VPC関連付け内のリソースから利用可能） / Allow mutual access without authentication from resources in the associated VPCs
  # ※個別に縛りたい場合はサービス側の auth_type を AWS_IAM にし、auth policy を設定 / Note: To restrict access per service, set the service auth_type to AWS_IAM and configure an auth policy
}

# ---- 2つのVPCを Service Network に関連付け ---- / Associate the two VPCs with the service network
resource "aws_vpclattice_service_network_vpc_association" "assoc" {
  for_each                   = { a = module.vpc_a.vpc_id, b = module.vpc_b.vpc_id }
  service_network_identifier = aws_vpclattice_service_network.sn.id
  vpc_identifier             = each.value
  tags                       = { Name = "${local.vpcs[each.key].name}-assoc" }
}

## 各VPCの EC2 を公開する Service / Target Group / Listener
# ---- Target Group (INSTANCE, HTTP:80) ----
resource "aws_vpclattice_target_group" "tg" {
  for_each = local.vpcs
  name     = "${each.value.name}-tg-80"
  type     = "INSTANCE"

  config {
    vpc_identifier = local.vpcs[each.key].vpc_id
    port           = 80
    protocol       = "HTTP"

    health_check {
      protocol = "HTTP"
      path     = "/"
      matcher {
        value = "200-399"
      }
    }
  }

  tags = { Name = "${each.value.name}-tg-80" }
}

# ---- 各 TG に該当 VPC の EC2 を登録（80/TCP）---- / Register the EC2 instance in each VPC with its target group on 80/TCP
resource "aws_vpclattice_target_group_attachment" "tg_attachment" {
  for_each                = aws_instance.ssm
  target_group_identifier = aws_vpclattice_target_group.tg[each.key].id
  target {
    id   = each.value.id
    port = 80
  }
}

# ---- Service（A/B） ----
resource "aws_vpclattice_service" "svc" {
  for_each  = local.vpcs
  name      = "${each.value.name}-svc"
  auth_type = "NONE" # まずは簡単に（必要なら AWS_IAM にし、auth policy を追加） / Keep it simple first. Use AWS_IAM and add an auth policy if needed.

  tags = { Name = "${each.value.name}-svc" }
}

# ---- Listener（HTTP:80 → 対応 TG へ）---- / Listener: HTTP:80 to the matching target group
resource "aws_vpclattice_listener" "listener" {
  for_each           = aws_vpclattice_service.svc
  name               = "${each.value.name}-listener"
  service_identifier = each.value.id
  port               = 80
  protocol           = "HTTP"

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.tg[each.key].id
        weight                  = 1
      }
    }
  }
}

# ---- Service を Service Network に関連付け ---- / Associate the service with the service network
resource "aws_vpclattice_service_network_service_association" "svc_assoc" {
  for_each                   = aws_vpclattice_service.svc
  service_network_identifier = aws_vpclattice_service_network.sn.id
  service_identifier         = each.value.id
  tags                       = { Name = "${local.vpcs[each.key].name}-svc-assoc" }
}

# ---- 出力 ---- / Outputs
output "lattice_service_domains" {
  description = "VPC Lattice service domains per VPC key (a/b)"
  value = {
    for k, s in aws_vpclattice_service.svc :
    k => s.dns_entry[0].domain_name
  }
}
