# =============================================================================
# VPC Module — main.tf
# Creates a production-ready VPC with public and private subnets,
# NAT Gateways, and the tags required for EKS auto-discovery.
# =============================================================================

locals {
  # Derive subnet CIDRs automatically from the VPC CIDR
  num_azs         = length(var.azs)
  public_cidrs    = [for i in range(local.num_azs) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_cidrs   = [for i in range(local.num_azs) : cidrsubnet(var.vpc_cidr, 4, i + local.num_azs)]
}

# ─── VPC ──────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                                          = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
  }
}

# ─── Internet Gateway ─────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# ─── Public Subnets ───────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count = local.num_azs

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "${var.cluster_name}-public-${var.azs[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

# ─── Private Subnets ──────────────────────────────────────────────────────────
resource "aws_subnet" "private" {
  count = local.num_azs

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name                                          = "${var.cluster_name}-private-${var.azs[count.index]}"
    "kubernetes.io/cluster/${var.cluster_name}"   = "owned"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

# ─── Elastic IPs for NAT Gateways ─────────────────────────────────────────────
resource "aws_eip" "nat" {
  count  = local.num_azs
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip-${var.azs[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

# ─── NAT Gateways (one per AZ for HA) ────────────────────────────────────────
resource "aws_nat_gateway" "main" {
  count = local.num_azs

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.cluster_name}-nat-${var.azs[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

# ─── Route Tables ─────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  count  = local.num_azs
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt-${var.azs[count.index]}"
  }
}

# ─── Route Table Associations ─────────────────────────────────────────────────
resource "aws_route_table_association" "public" {
  count          = local.num_azs
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = local.num_azs
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ─── VPC Flow Logs ────────────────────────────────────────────────────────────
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-flow-logs"
  }
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.cluster_name}/flow-logs"
  retention_in_days = 30
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.cluster_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.cluster_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}
