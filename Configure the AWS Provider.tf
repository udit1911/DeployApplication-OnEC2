# Configure the AWS Provider
provider "aws" {
  region = "ap-south-1" # Replace with your desired AWS region
}

# Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "MyVPC"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "MyIGW"
  }
}

# Create a public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.16.0/20"
  map_public_ip_on_launch = true

  tags = {
    Name = "PublicSubnet"
  }
}

# Create a security group for the EC2 instances
resource "aws_security_group" "my_sg" {
  name        = "AllowHTTPHTTPS"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.my_vpc.id

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

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

# Create an EC2 instance
resource "aws_instance" "my_instance" {
  ami           = "ami-05295b6e6c790593e" # Replace with your desired AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.my_sg.id]

  tags = {
    Name = "MyInstance"
  }
}

# Create an Auto Scaling group
resource "aws_autoscaling_group" "my_asg" {
  name                      = "web auto"
  max_size                  = 1
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = true
  launch_configuration      = aws_launch_configuration.my_lc.name
  vpc_zone_identifier       = [aws_subnet.public_subnet.id]
}

# Create a launch configuration for the Auto Scaling group
resource "aws_launch_configuration" "my_lc" {
  name_prefix     = "MyLC-"
  image_id        = "ami-05295b6e6c790593e" # Replace with your desired AMI
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.my_sg.id]
}

# Create an Elastic Load Balancer
resource "aws_elb" "my_elb" {
  name            = "webauto1"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.my_sg.id]

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTP:80/"
  }

  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = "80"
    instance_protocol = "http"
  }
}

# Attach the Auto Scaling group to the Elastic Load Balancer
resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.my_asg.id
  elb                    = aws_elb.my_elb.id
}

# Create a CloudFront distribution and attach it to the Elastic Load Balancer
resource "aws_cloudfront_distribution" "my_distribution" {
  origin {
    domain_name = aws_elb.my_elb.dns_name
    origin_id   = "webauto1"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "myElbOrigin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Create a CloudWatch metric alarm for monitoring the EC2 instances
resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "HighCPUUtilization"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.my_asg.name
  }

  alarm_description = "This metric monitors high CPU utilization on EC2 instances"
  alarm_actions     = ["${aws_autoscaling_policy.my_policy.arn}"]
}

# Create an Auto Scaling policy for scaling up instances
resource "aws_autoscaling_policy" "my_policy" {
  name                   = "ScaleUpPolicy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.my_asg.name
}