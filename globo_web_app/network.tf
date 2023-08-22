##################################################################################
# DATA
##################################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
module "app" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.1.1"

  cidr = var.vpc_cidr_block

  azs             = slice(data.aws_availability_zones.available.names, 0, var.vpc_public_subnet_count)
  public_subnets  = [for subnet in range(var.vpc_public_subnet_count): cidrsubnet(var.vpc_cidr_block, 8, subnet)]

  enable_nat_gateway = false
  enable_vpn_gateway = false
  enable_dns_hostnames = var.enable_dns_hostnames
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

resource "aws_vpc" "app" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.common_tags, {
    Name = "${local.naming_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id

  tags = merge(local.common_tags, {
    Name = "${local.naming_prefix}-igw"
  })
}

resource "aws_subnet" "public_subnets" {
  count                   = var.vpc_public_subnet_count
  cidr_block              = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  vpc_id                  = aws_vpc.app.id
  map_public_ip_on_launch = var.map_public_ip_on_launch
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.naming_prefix}-subnet-${count.index}"
  })
}

# ROUTING #
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.naming_prefix}-rtb"
  })
}

resource "aws_route_table_association" "app_public_subnets" {
  count          = var.vpc_public_subnet_count
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.app.id
}

# SECURITY GROUPS #
# Nginx security group 
resource "aws_security_group" "nginx_sg" {
  name   = "${local.naming_prefix}-nginx_sg"
  vpc_id = aws_vpc.app.id

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_security_group" "alb_sg" {
  name   = "nginx_alb_sg"
  vpc_id = aws_vpc.app.id

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}


