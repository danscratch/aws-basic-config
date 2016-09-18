variable "aws_region" {
  description = "AWS region to launch servers."
  default = "us-east-1"
}

variable "domain_name" {
  default = "everythingisawesome"
}

variable "key_name" {
  default = "everythingisawesome-keypair"
}

# Ubuntu 14.04 EBS-SSD
variable "aws_ami" {
  default = "ami-8e0b9499"    # or really, whatever you want
}

variable "cert_arn" {
  # You should create a cert using the AWS certificate manager, then paste its full "arn" here
  # default = "arn:aws:acm:us-east-1:foo-bar"
  default = "arn:aws:acm:us-east-1:1234567890:certificate/1111111-11111-11111-11111111111"
}

variable "alias_zone_id" {
  description = "hardcoded constant zone_id that is used for all CloudFront distributions"
  default = "Z2FDTNDATAQYW2"  # DO NOT EDIT
}

variable "my_ip_address" {
  description = "this will be used as a safe ip address"
  default = "1.2.3.4/32"
}
