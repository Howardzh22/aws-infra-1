

module "s3_bucket" {
  source      = "./module/s3"
  bucket_name = var.bucket_name
  acl_value   = var.acl_value
}

module "VPC" {
  source = "./module/vpc"
  cidr   = var.cidr
}
module "security_groups" {
  source = "./module/security-group"
  vpc_id = module.VPC.vpc_id
}

data "template_file" "user_data" {

  template = <<EOF

  #!/bin/bash
  echo "DATABASE_HOST=${replace(aws_db_instance.RDS.endpoint, "/:.*/", "")}" >> /home/ec2-user/.env 
  echo "DATABASE_NAME=${aws_db_instance.RDS.db_name}" >> /home/ec2-user/.env 
  echo "DATABASE_USERNAME=${aws_db_instance.RDS.username}" >> /home/ec2-user/.env 
  echo "DATABASE_PASSWORD=${aws_db_instance.RDS.password}" >> /home/ec2-user/.env 
  echo "DIALECT=${aws_db_instance.RDS.engine}" >> /home/ec2-user/.env 
  echo "BUCKET_NAME=${module.s3_bucket.mybucket.bucket}" >> /home/ec2-user/.env 
  echo "BUCKET_REGION=${var.region}" >> /home/ec2-user/.env
  mv /home/ec2-user/.env /home/ec2-user/webapp/.env 
  mv /tmp/cloudwatch-config.json /opt/cloudwatch-config.json
  sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/cloudwatch-config.json \
  -s

  EOF

}
resource "aws_launch_template" "launch_conf" {
  name          = "asg_launch_config"
  image_id      = data.aws_ami.app_ami.id
  instance_type = "t2.micro"
  key_name      = data.aws_key_pair.ec2_key.key_name
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [module.security_groups.app_sg.id]
    //subnet_id                   = aws_subnet.public_subnets[0].id
  }
  user_data = base64encode(data.template_file.user_data.rendered)
  iam_instance_profile {
    name = aws_iam_instance_profile.attach-profile.name
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      kms_key_id = aws_kms_key.ebs.arn
      encrypted  = true

    }
  }
}
resource "aws_autoscaling_group" "asg_group" {
  name_prefix         = "asg_group"
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  default_cooldown    = 60
  min_size            = 1
  max_size            = 3
  desired_capacity    = 1
  target_group_arns   = [aws_lb_target_group.lb_tg.arn]
  launch_template {
    id      = aws_launch_template.launch_conf.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "asg_group"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "scale_up_policy"
  autoscaling_group_name = aws_autoscaling_group.asg_group.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
}

resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name          = "scale_up_alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  threshold           = 5
  period              = 60
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg_group.name
  }
  alarm_actions = [aws_autoscaling_policy.scale_up_policy.arn]
}

resource "aws_autoscaling_policy" "scale_down_policy" {
  name                   = "scale_down_policy"
  autoscaling_group_name = aws_autoscaling_group.asg_group.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
}

resource "aws_cloudwatch_metric_alarm" "scale_down_alarm" {
  alarm_name          = "scale_down_alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  threshold           = 3
  period              = 60
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg_group.name
  }
  alarm_actions = [aws_autoscaling_policy.scale_down_policy.arn]
}


resource "aws_lb" "load_balancer" {
  name               = "csye6225-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.security_groups.lb_sg.id]
  subnets            = aws_subnet.public_subnets.*.id
  tags = {
    Application = "WebApp"
  }
}

resource "aws_lb_target_group" "lb_tg" {
  name        = "lb-tg"
  target_type = "instance"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.VPC.vpc_id

  health_check {
    port     = 8080
    path     = "/healthz"
    protocol = "HTTP"
  }

}



resource "aws_lb_listener" "lb_lis" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:525527600142:certificate/6753e816-94af-47f5-aab9-0f5e0ca3ed62"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lb_tg.arn
  }
}

resource "aws_subnet" "public_subnets" {
  count             = 3
  vpc_id            = module.VPC.vpc_id
  cidr_block        = cidrsubnet(var.cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = module.VPC.vpc_id
  cidr_block        = cidrsubnet(var.cidr, 8, count.index + 4)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = module.VPC.vpc_id

  tags = {
    Name = "main VPC IG"
  }
}

resource "aws_route_table" "public" {
  vpc_id = module.VPC.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route_table" "private" {
  vpc_id = module.VPC.vpc_id

  route = []

  tags = {
    Name = "Private Route Table"
  }
}

resource "aws_route_table_association" "public_subnet_asso" {
  count          = 3
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_subnet_asso" {
  count          = 3
  subnet_id      = element(aws_subnet.private_subnets[*].id, count.index)
  route_table_id = aws_route_table.private.id
}

data "aws_ami" "app_ami" {
  most_recent = true
  name_regex  = "csye6225-*"
  owners      = ["539751877006"]
}

data "aws_key_pair" "ec2_key" {
  key_pair_id = var.key_pair_id
}

data "aws_route53_zone" "demo_zone" {
  name = var.zone_name
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
resource "aws_iam_role_policy_attachment" "run-cloudWatch-policy-attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
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
  vpc_security_group_ids = [module.security_groups.db_sg.id]
  parameter_group_name   = aws_db_parameter_group.RDSparameter.name
  apply_immediately      = true
  skip_final_snapshot    = true
  kms_key_id             = aws_kms_key.rds.arn
  storage_encrypted      = true
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

resource "aws_route53_record" "myrecord" {
  zone_id = data.aws_route53_zone.demo_zone.zone_id
  name    = var.zone_name
  type    = "A"
  alias {
    name                   = aws_lb.load_balancer.dns_name
    zone_id                = aws_lb.load_balancer.zone_id
    evaluate_target_health = true
  }
}

data "aws_caller_identity" "current" {
}
resource "aws_kms_key" "ebs" {
  description = "Encrypte EBS volumes"
  policy = jsonencode({
    "Id" : "key-consolepolicy-3",
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "Enable IAM User Permissions",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : "arn:aws:iam::525527600142:root"
        },
        "Action" : "kms:*",
        "Resource" : "*"
      },
      {
        "Sid" : "Allow access for Key Administrators",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : [
            "arn:aws:iam::525527600142:role/aws-service-role/elasticloadbalancing.amazonaws.com/AWSServiceRoleForElasticLoadBalancing",
            "arn:aws:iam::525527600142:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
          ]
        },
        "Action" : [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "Allow use of the key",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : [
            "arn:aws:iam::525527600142:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
            "arn:aws:iam::525527600142:role/aws-service-role/elasticloadbalancing.amazonaws.com/AWSServiceRoleForElasticLoadBalancing"
          ]
        },
        "Action" : [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "Allow attachment of persistent resources",
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : [
            "arn:aws:iam::525527600142:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
            "arn:aws:iam::525527600142:role/aws-service-role/elasticloadbalancing.amazonaws.com/AWSServiceRoleForElasticLoadBalancing"
          ]
        },
        "Action" : [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        "Resource" : "*",
        "Condition" : {
          "Bool" : {
            "kms:GrantIsForAWSResource" : "true"
          }
        }
      }
    ]
  })
}

resource "aws_kms_key" "rds" {
  description = "Encrypte RDS Instances"
}
