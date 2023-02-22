/*
module "mynetwork" {

  source = "./module/networking"
  cidr   = "10.0.0.0/16"
}
*/
resource "aws_vpc" "main" {
  cidr_block = var.cidr
  tags = {
    Name = "MyVPC"
  }

}

resource "aws_security_group" "application" {
  name        = "application"
  description = "allow on port 22,80,443,8080"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

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

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route = []

  tags = {
    Name = "Private Route Table"
  }
}

resource "aws_route_table_association" "public_subnet_asso" {
  //count = length(var.public_subnet_cidrs)
  count          = 3
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_subnet_asso" {
  //count = length(var.private_subnet_cidrs)
  count          = 3
  subnet_id      = element(aws_subnet.private_subnets[*].id, count.index)
  route_table_id = aws_route_table.private.id
}


/*
module "mynetwork2" {

  source = "./module/networking"
  cidr   = "10.20.0.0/16"
}
*/

data "aws_ami" "app_ami" {
  most_recent = true
  name_regex  = "csye6225-*"
  owners      = ["self"]
}

data "aws_key_pair" "ec2_key" {
  key_pair_id = var.key_pair_id
}

resource "aws_instance" "webapp" {
  instance_type               = "t2.micro"
  ami                         = data.aws_ami.app_ami.id
  vpc_security_group_ids      = [aws_security_group.application.id]
  subnet_id                   = aws_subnet.public_subnets[0].id
  associate_public_ip_address = true
  key_name                    = data.aws_key_pair.ec2_key.key_name
  root_block_device {
    volume_size = 50
    volume_type = "gp2"
  }
  tags = {
    Name = "MyVPCinstance"
  }
}


