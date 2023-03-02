variable "cidr" {
  type = string
}

variable "profile" {
  type = string
}


variable "region" {
  type = string
}

data "aws_availability_zones" "available" {
  state = "available"
}

variable "key_pair_id" {
  type = string
}

variable "bucket_name" {}

variable "acl_value" {
  type = string
}

variable "application_SG" {
  type = string
}

variable "database_SG" {
  type = string
}