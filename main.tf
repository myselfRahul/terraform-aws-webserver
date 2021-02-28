terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-southeast-1"
  access_key = "XXXXXXXXXXXXXXXXXXXXXXXXXXX"
  secret_key = "XXXXXXXXXXXXXXXXXXXXXXXXXX"
}
# Create VPC

resource "aws_vpc" "web-app-vpc" {
  cidr_block = "10.0.0.0/16"

   tags = {
    Name = "Web Application VPC"
  }
}

# Create Internet gateway
resource "aws_internet_gateway" "gw" {
 vpc_id = aws_vpc.web-app-vpc.id 
}

#Custom Route Table 

resource "aws_route_table" "web-app-route-table" {
  vpc_id = aws_vpc.web-app-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id =aws_internet_gateway.gw.id 
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id             =aws_internet_gateway.gw.id
  }

  tags = {
    Name = "web application gateway"
  }
}


# Create public Subnet

resource "aws_subnet" "sebnet-1" {
  vpc_id     = aws_vpc.web-app-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-southeast-1a"

  tags = {
    Name = "Web public Subnet"
  }
}


# Create private Subnet

resource "aws_subnet" "sebnet-2" {
  vpc_id     = aws_vpc.web-app-vpc.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "ap-southeast-1b"

  tags = {
    Name = "Web private Subnet"
  }
}

#Load Balancer

resource "aws_lb_target_group" "my-target-group" {
  health_check {
    interval            = 10
    path                = "/var/www/html/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  name        = "my-test-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.web-app-vpc.id
}


resource "aws_lb" "my-aws-alb" {
  name     = "my-test-alb"
  internal = false

  security_groups = [
    aws_security_group.my-alb-sg.id
  ]

  subnets = [aws_subnet.sebnet-1.id,aws_subnet.sebnet-2.id]

  tags = {
    Name = "my-test-alb"
  }

  ip_address_type    = "ipv4"
  load_balancer_type = "application"
}

resource "aws_lb_listener" "my-http-alb-listner" {
  load_balancer_arn = aws_lb.my-aws-alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my-target-group.arn
  }
}


resource "aws_lb_listener" "my-https-alb-listner" {
  load_balancer_arn = aws_lb.my-aws-alb.arn
  port              = 443
  protocol          = "HTTPS"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my-target-group.arn
  }
}
resource "aws_security_group" "my-alb-sg" {
  name   = "my-alb-sg"
  vpc_id = aws_vpc.web-app-vpc.id 
}

resource "aws_security_group_rule" "inbound_ssh" {
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.my-alb-sg.id
  to_port           = 22
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "inbound_http" {
  from_port         = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.my-alb-sg.id
  to_port           = 80
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "inbound_https" {
  from_port         = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.my-alb-sg.id
  to_port           = 443
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}


resource "aws_security_group_rule" "outbound_all" {
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.my-alb-sg.id
  to_port           = 0
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Associate Subnet with Route Table

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.sebnet-1.id
  route_table_id =  aws_route_table.web-app-route-table.id

}

resource "aws_network_interface" "web-nic" {
  subnet_id       = aws_subnet.sebnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.my-alb-sg.id]

}

# Assign an Elastic IP to the Network Interface which is created above 

resource "aws_eip" "one" {
  vpc                       = true
  network_interface         =aws_network_interface.web-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}


# Create Ubuntu Server and install/enable apache2
resource "aws_instance" "web-server-instance" {

    ami = "ami-09a6a7e49bd29554b"
    instance_type = "t2.micro"
    availability_zone = "ap-southeast-1a"
    key_name = "my-ssh-key"
        network_interface {
          device_index = 0
        network_interface_id = aws_network_interface.web-nic.id
    }
        user_data = <<-EOF
                     #!/bin/bash
                     sudo apt-get update -y
                     sudo apt-get install apache2
                     sudo echo "Congrats ! You have Successfully Created WebServer > /var/www/html/index.html"
                     EOF
     tags = {
       "Name" = "First Web Server ..."
     }                     
}
