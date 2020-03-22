resource "aws_vpc" "vpc" {
  cidr_block           = var.VPC_CIDR
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${lower(var.PROJECT)}-vpc"
    Project = lower(var.PROJECT)
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name    = "${lower(var.PROJECT)}-igw"
    Project = lower(var.PROJECT)
  }
}

resource "aws_vpc_dhcp_options" "dhcp_options" {
  domain_name = var.DOMAIN_NAME

  tags = {
    Name    = "${lower(var.PROJECT)}-dopt"
    Project = lower(var.PROJECT)
  }
}

resource "aws_vpc_dhcp_options_association" "dhcp_options_association" {
  vpc_id          = aws_vpc.vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.dhcp_options.id
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.PUBLIC_SN_A_CIDR
  availability_zone = "${var.AWS_REGION}a"

  tags = {
    Name                     = "${lower(var.PROJECT)}-public-sn-a"
    Project                  = lower(var.PROJECT)
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.PUBLIC_SN_B_CIDR
  availability_zone = "${var.AWS_REGION}b"

  tags = {
    Name                     = "${lower(var.PROJECT)}-public-sn-b"
    Project                  = lower(var.PROJECT)
    "kubernetes.io/role/elb" = "1"
  }
}


resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.PRIVATE_SN_A_CIDR
  availability_zone = "${var.AWS_REGION}a"

  tags = {
    Name                              = "${lower(var.PROJECT)}-private-sn-a"
    Project                           = lower(var.PROJECT)
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.PRIVATE_SN_B_CIDR
  availability_zone = "${var.AWS_REGION}b"

  tags = {
    Name                              = "${lower(var.PROJECT)}-private-sn-b"
    Project                           = lower(var.PROJECT)
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_eip" "nat_eip" {
  vpc = true

  tags = {
    Name    = "${lower(var.PROJECT)}-nat-eip"
    Project = lower(var.PROJECT)
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_a.id

  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name    = "${lower(var.PROJECT)}-nat"
    Project = lower(var.PROJECT)
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name    = "${lower(var.PROJECT)}-public-rt"
    Project = lower(var.PROJECT)
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name    = "${lower(var.PROJECT)}-private-rt"
    Project = lower(var.PROJECT)
  }
}

resource "aws_route_table_association" "public_rt_association_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rt_association_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rt_association_a" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_rt_association_b" {
  subnet_id      = aws_subnet.private_subnet_b.id
  route_table_id = aws_route_table.private_rt.id
}
