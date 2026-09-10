# Networking inputs for the load-balanced tiers.
#
# The project runs in the account's default VPC. A load balancer needs subnets
# in at least two availability zones, and not every AZ offers every instance
# type (us-east-1e famously does not offer t3.micro), so the default subnets
# are filtered down to AZs that can actually launch our instances.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

data "aws_ec2_instance_type_offerings" "app" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

locals {
  usable_subnet_ids = [
    for subnet in data.aws_subnet.default : subnet.id
    if contains(data.aws_ec2_instance_type_offerings.app.locations, subnet.availability_zone)
  ]
}
