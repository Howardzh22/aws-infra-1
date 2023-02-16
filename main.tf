/*
module "mynetwork" {

  source = "./module/networking"
  cidr   = "10.0.0.0/16"
}
*/
resource "aws_vpc" "main" {
  cidr_block = var.cidr
}

resource "aws_subnet" "public_subnets" {
  //count             = length(var.public_subnet_cidrs)
  count  = 3
  vpc_id = aws_vpc.main.id
  //cidr_block        = element(var.public_subnet_cidrs, count.index)
  cidr_block = cidrsubnet(var.cidr, 8, count.index)
  //availability_zone = element(var.azs, count.index)

  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  //count             = length(var.private_subnet_cidrs)
  count  = 3
  vpc_id = aws_vpc.main.id
  //cidr_block        = element(var.private_subnet_cidrs, count.index)
  cidr_block = cidrsubnet(var.cidr, 8, count.index + 4)
  //availability_zone = element(var.azs, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main VPC IG"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route_table_association" "public_subnet_asso" {
  //count = length(var.public_subnet_cidrs)
  count          = 3
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

/*
module "mynetwork2" {

  source = "./module/networking"
  cidr   = "10.20.0.0/16"
}
*/


