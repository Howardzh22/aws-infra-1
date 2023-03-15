/*
module "mynetwork" {

  source = "./module/networking"
  cidr   = "10.0.0.0/16"
}
*/

module "s3_bucket" {
  source      = "./s3"
  bucket_name = var.bucket_name
  acl_value   = var.acl_value
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket = module.s3_bucket.mybucket.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

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

resource "aws_security_group" "database" {
  name        = "database"
  description = "allow on port 3306, and restrict access to the instance from the internet"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
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

data "aws_ami" "app_ami" {
  most_recent = true
  name_regex  = "csye6225-*"
  owners      = ["self"]
}

data "aws_key_pair" "ec2_key" {
  key_pair_id = var.key_pair_id
}

resource "aws_iam_policy" "mys3policy" {
  name        = "WebAppS3"
  description = "allow EC2 instances to perform S3 buckets"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "s3:ListAllMyBuckets",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:GetObjectAcl",
          "s3:DeleteObject"
        ],
        "Effect" : "Allow",
        "Resource" : [
          "arn:aws:s3:::${module.s3_bucket.mybucket.id}",
          "arn:aws:s3:::${module.s3_bucket.mybucket.id}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "ec2_role" {
  name = "EC2-CSYE6225"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "my-policy-attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.mys3policy.arn
}

resource "aws_iam_instance_profile" "attach-profile" {
  name = "attach_profile"
  role = aws_iam_role.ec2_role.name
}


resource "aws_db_instance" "RDS" {
  allocated_storage      = 50
  max_allocated_storage  = 100
  db_name                = "csye6225"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  username               = "csye6225"
  password               = "csye6225ZH!"
  identifier             = "csye6225"
  publicly_accessible    = false
  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.database.id]
  parameter_group_name   = aws_db_parameter_group.RDSparameter.name
  apply_immediately      = true
  skip_final_snapshot    = true
  tags = {
    Name = "RDS Instance"
  }
}

resource "aws_db_subnet_group" "db_subnet" {
  name       = "db_subnet"
  subnet_ids = ["${aws_subnet.private_subnets[0].id}", "${aws_subnet.private_subnets[1].id}", "${aws_subnet.private_subnets[2].id}"]

  tags = {
    Name = "db_subnet"
  }
}

resource "aws_db_parameter_group" "RDSparameter" {
  name   = "my-pg"
  family = "mysql8.0"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "webapp" {
  instance_type               = "t2.micro"
  ami                         = data.aws_ami.app_ami.id
  vpc_security_group_ids      = [aws_security_group.application.id]
  subnet_id                   = aws_subnet.public_subnets[0].id
  associate_public_ip_address = true
  key_name                    = data.aws_key_pair.ec2_key.key_name
  disable_api_termination     = false

  iam_instance_profile = aws_iam_instance_profile.attach-profile.name
  root_block_device {
    volume_size = 50
    volume_type = "gp2"
  }
  tags = {
    Name = "MyVPCinstance"
  }

  user_data = <<EOF
    #!/bin/bash
    echo "DATABASE_HOST=${replace(aws_db_instance.RDS.endpoint, "/:.*/", "")}" >> /home/ec2-user/.env 
    echo "DATABASE_NAME=${aws_db_instance.RDS.db_name}" >> /home/ec2-user/.env 
    echo "DATABASE_USERNAME=${aws_db_instance.RDS.username}" >> /home/ec2-user/.env 
    echo "DATABASE_PASSWORD=${aws_db_instance.RDS.password}" >> /home/ec2-user/.env 
    echo "DIALECT=${aws_db_instance.RDS.engine}" >> /home/ec2-user/.env 
    echo "BUCKET_NAME=${module.s3_bucket.mybucket.bucket}" >> /home/ec2-user/.env 
    echo "BUCKET_REGION=${var.region}" >> /home/ec2-user/.env
    mv /home/ec2-user/.env /home/ec2-user/webapp/.env 
    EOF
}