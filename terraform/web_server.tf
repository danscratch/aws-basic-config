
#############################
# IAM

resource "aws_iam_role" "web_iam_role" {
  name = "web_iam_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "web_instance_profile" {
  name = "web_instance_profile"
  roles = ["web_iam_role"]
}

resource "aws_iam_role_policy" "web_iam_role_policy" {
  name = "web_iam_role_policy"
  role = "${aws_iam_role.web_iam_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::${var.domain_name}-release"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:List*"
      ],
      "Resource": [
        "arn:aws:s3:::${var.domain_name}-release/*"
      ]
    }
  ]
}
EOF
}

#############################
# ELB

resource "aws_elb" "prod" {
  name = "${var.domain_name}-prod-elb"

  subnets         = ["${aws_subnet.subnet_east_1b.id}", "${aws_subnet.subnet_east_1c.id}"]
  security_groups = ["${aws_security_group.world_visible_lb.id}"]
  instances       = ["${aws_instance.web.id}"]

  listener {
    instance_port     = 81
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 443
    lb_protocol       = "https"
    ssl_certificate_id  = "${var.cert_arn}"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:80/api/ping"
    interval = 5
  }
}


#####################
# DNS

resource "aws_route53_record" "raw" {
  zone_id = "${aws_route53_zone.public.zone_id}"
  name = "${var.domain_name}.com"
  type = "A"

  alias {
    name = "${aws_elb.prod.dns_name}"
    zone_id = "${aws_elb.prod.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "www" {
  zone_id = "${aws_route53_zone.public.zone_id}"
  name = "www"
  type = "A"

  alias {
    name = "${aws_elb.prod.dns_name}"
    zone_id = "${aws_elb.prod.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cdn_www" {
  zone_id = "${aws_route53_zone.public.zone_id}"
  name = "cdn-www"
  type = "A"

  alias {
    name = "${aws_cloudfront_distribution.web_cloudfront.domain_name}"
    zone_id = "${var.alias_zone_id}"
    evaluate_target_health = false
  }
}

#############################
# EC2 INSTANCE

resource "aws_instance" "web" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "ubuntu"

    # The connection will use the local SSH agent for authentication.
  }

  instance_type = "t2.micro"
  iam_instance_profile = "${aws_iam_instance_profile.web_instance_profile.id}"

  # Lookup the correct AMI based on the region
  # we specified
  ami = "${var.aws_ami}"

  # The name of our SSH keypair we created above.
  key_name = "${var.key_name}"

  # Our Security group to allow access from the load balancer
  vpc_security_group_ids = [
    "${aws_security_group.lb_to_web_server.id}",
    "${aws_security_group.ssh_whitelist.id}",
    "${aws_security_group.world_visible_ports.id}"
  ]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = "${aws_subnet.subnet_east_1b.id}"

  # We run a remote provisioner on the instance after creating it.
  # In this case, we just install nginx and start it. By default,
  # this should be on port 80
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "curl -sL https://deb.nodesource.com/setup_6.x | sudo bash -",
      "sudo apt-get -y install nginx git nodejs build-essential puppet",
      "sudo npm install -g pm2",
      "curl -O https://bootstrap.pypa.io/get-pip.py",
      "sudo python get-pip.py",
      "sudo pip install awscli"
    ]
  }

  tags {
    Name = "${var.domain_name}-web"
    SystemName = "web"
  }
}

#############################
# CLOUDFRONT

resource "aws_s3_bucket" "web_cdn" {
  bucket = "cdn-www.${var.domain_name}.com"
  acl = "private"
  versioning {
    enabled = false
  }
  tags {
    Name = "cdn-www.${var.domain_name}.com"
  }
}

resource "aws_cloudfront_distribution" "web_cloudfront" {
  enabled = true
  comment = "CDN for the web servers"
  default_root_object = "index.html"
  price_class = "PriceClass_All"
  aliases = ["cdn-www.${var.domain_name}.com"]

  origin {
    domain_name = "cdn-www.${var.domain_name}.com.s3.amazonaws.com"
    origin_id   = "cdn-www"
  }

  default_cache_behavior {
    viewer_protocol_policy = "https-only"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    viewer_protocol_policy = "allow-all"
    target_origin_id = "cdn-www"
    min_ttl = 0
    default_ttl = 86400
    max_ttl = 31536000

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = "${var.cert_arn}"
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1"
  }
}
