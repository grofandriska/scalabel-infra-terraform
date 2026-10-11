# ---------------------------------------------------------------------------
# List -> map transzformáció: a subnet neve lesz a for_each kulcs, így egy
# subnet hozzáadása/törlése nem érinti a többit (count-tal elcsúsznának az indexek).
# ---------------------------------------------------------------------------
locals {
  subnets         = { for s in var.subnets : s.name => s }
  public_subnets  = { for k, s in local.subnets : k => s if s.type == "public" }
  private_subnets = { for k, s in local.subnets : k => s if s.type == "private" }

  # Azok a public subnetek, ahová NAT gateway kerül
  nat_subnets = { for k, s in local.public_subnets : k => s if s.nat_gateway }
  nat_keys    = sort(keys(local.nat_subnets))

  # AZ => [NAT-ot tartalmazó public subnet nevek]  (a "..." csoportosít)
  nat_by_az = { for k, s in local.nat_subnets : s.az => k... }

  # Minden private subnet: elsősorban a saját AZ-jában lévő NAT-ot használja,
  # ha ott nincs, az első NAT-ot; ha egyáltalán nincs NAT, akkor null.
  private_nat = {
    for k, s in local.private_subnets :
    k => try(local.nat_by_az[s.az][0], local.nat_keys[0], null)
  }
}

# ----------------------------- VPC -----------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_config.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = var.vpc_config.enable_dns_hostnames

  tags = { Name = "${var.name_prefix}-vpc" }
}

# ----------------------------- Subnetek ------------------------------------
resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.type == "public"

  tags = {
    Name = "${var.name_prefix}-${each.key}"
    Tier = each.value.type
  }
}

# ----------------------------- Gatewayek -----------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_eip" "nat" {
  for_each = local.nat_subnets

  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-nat-eip-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_subnets

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[each.key].id

  tags = { Name = "${var.name_prefix}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

# ----------------------------- Route table-ök ------------------------------
# Public: egy közös route table, 0.0.0.0/0 -> IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

# Private: subnetenként saját route table, 0.0.0.0/0 -> NAT GW
resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-${each.key}-rt" }
}

resource "aws_route" "private_nat" {
  for_each = { for k, nat in local.private_nat : k => nat if nat != null }

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.value].id
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

# Figyelmeztetés (nem hiba), ha vannak private subnetek, de nincs NAT
check "private_subnets_have_nat" {
  assert {
    condition     = length(local.private_subnets) == 0 || length(local.nat_subnets) > 0
    error_message = "Vannak private subnetek, de egy public subneten sincs nat_gateway = true, így nem érik el az internetet."
  }
}