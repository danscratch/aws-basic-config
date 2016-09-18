# Specify the provider and access details
provider "aws" {
  region = "${var.aws_region}"
}

# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags {
    Name = "${var.domain_name}-vpc"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
  tags {
    Name = "${var.domain_name}-gateway"
  }
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# Create a subnet to launch our instances into
resource "aws_subnet" "subnet_east_1b" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags {
    Name = "${var.domain_name}-subnet-east-1b"
  }
}

resource "aws_subnet" "subnet_east_1c" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.10.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1c"
  tags {
    Name = "${var.domain_name}-subnet-east-1c"
  }
}

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "world_visible_lb" {
  name        = "world_visible_lb"
  description = "security group for the ELB so it is accessible via the web"
  vpc_id      = "${aws_vpc.default.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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
}

# security group for the web server so it can be accessed from the load balancer
resource "aws_security_group" "lb_to_web_server" {
  name        = "lb_to_web_server"
  description = "security group for the web server so it can be accessed from the load balancer"
  vpc_id      = "${aws_vpc.default.id}"

  # HTTP access from the load balancer
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = ["${aws_security_group.world_visible_lb.id}"]
  }

  # HTTP access from the load balancer (you should redirect all requests to port 81 to https)
  # nginx code:
  #   server {
  #     listen       81;
  #     server_name _; # Default virtual host
  #     return 301 https://$host$request_uri;
  #   }
  ingress {
    from_port   = 81
    to_port     = 81
    protocol    = "tcp"
    security_groups = ["${aws_security_group.world_visible_lb.id}"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# whitelist of IP addresses able to ssh in
resource "aws_security_group" "ssh_whitelist" {
  name        = "ssh_whitelist"
  description = "whitelist of IP addresses able to ssh in"
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip_address}"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ports that should be visible to the world
resource "aws_security_group" "world_visible_ports" {
  name        = "world_visible_ports"
  description = "ports that should be visible to the world"
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}
