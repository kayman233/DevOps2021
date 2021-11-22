provider "aws" {
    region = "us-west-2"
}

variable "server_port" {
    type = number
    default = 8080
}

data "aws_vpc" "default" {
    default = true
}

data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id
}

#------------------Configuration

resource "aws_launch_configuration" "webapp-1" {
    image_id = "ami-06e54d05255faf8f6"
    instance_type = "t2.micro"
    
    user_data = <<-EOF
                #!/bin/bash
                mkdir -p webapp-1
                echo "<h2>Hello from WebApp-1</h2>" > webapp-1/index.html
                nohup busybox httpd -f -p ${var.server_port} &
                EOF
    
    security_groups = [aws_security_group.instance.id]

    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_launch_configuration" "webapp-2" {
    image_id = "ami-06e54d05255faf8f6"
    instance_type = "t2.micro"
    
    user_data = <<-EOF
                #!/bin/bash
                mkdir -p webapp-2
                echo "<h2>Hello from WebApp-2 </h2>" > webapp-2/index.html
                nohup busybox httpd -f -p ${var.server_port} &
                EOF
    
    security_groups = [aws_security_group.instance.id]

    lifecycle {
        create_before_destroy = true
    }
}

#------------------ASG

resource "aws_autoscaling_group" "webapp-1" {
    launch_configuration = aws_launch_configuration.webapp-1.name

    vpc_zone_identifier = data.aws_subnet_ids.default.ids
    min_size = 2
    max_size = 10
    tag {
        key = "Name"
        value = "terraform-asg-webapp-1"
        propagate_at_launch = true
    }

    target_group_arns = [aws_lb_target_group.webapp-1.arn]
    health_check_type = "ELB"
}

resource "aws_autoscaling_group" "webapp-2" {
    launch_configuration = aws_launch_configuration.webapp-2.name

    vpc_zone_identifier = data.aws_subnet_ids.default.ids
    min_size = 2
    max_size = 10
    tag {
        key = "Name"
        value = "terraform-asg-webapp-2"
        propagate_at_launch = true
    }

    target_group_arns = [aws_lb_target_group.webapp-2.arn]
    health_check_type = "ELB"
}

#------------------Target group

resource "aws_lb_target_group" "webapp-1" {
    name = "terraform-webapp-1-example"
    port = var.server_port
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id

    health_check {
        path = "/webapp-1/index.html"
        protocol = "HTTP"
        matcher = "200"
        interval = 15
        timeout = 3
        healthy_threshold = 2
        unhealthy_threshold = 2
    }
}

resource "aws_lb_target_group" "webapp-2" {
    name = "terraform-foo-example"
    port = var.server_port
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id

    health_check {
        path = "/webapp-2/index.html"
        protocol = "HTTP"
        matcher = "200"
        interval = 15
        timeout = 3
        healthy_threshold = 2
        unhealthy_threshold = 2
    }
}

#------------------Listener rule


resource "aws_lb_listener_rule" "webapp-1" {
    listener_arn = aws_lb_listener.http.arn
    priority = 100

    condition {
        path_pattern {
            values = ["/webapp-1/*"]
        }
    }
    
    action {
        type = "forward"
        target_group_arn = aws_lb_target_group.webapp-1.arn
    }
}

resource "aws_lb_listener_rule" "webapp-2" {
    listener_arn = aws_lb_listener.http.arn
    priority = 101

    condition {
        path_pattern {
            values = ["/webapp-2/*"]
        }
    }
    
    action {
        type = "forward"
        target_group_arn = aws_lb_target_group.webapp-2.arn
    }
}

#------------------Load balancer

resource "aws_lb" "example" {
    name = "terraform-asg-example"
    load_balancer_type = "application"
    subnets = data.aws_subnet_ids.default.ids
    security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.example.arn
    port = 80
    protocol = "HTTP"

    default_action {
        type = "fixed-response"

        fixed_response {
            content_type = "text/plain"
            message_body = "404: page not found"
            status_code = 404
        }
    }
}

#------------------Security group

resource "aws_security_group" "alb" {
    name = "terraform-example-alb"

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "instance" {
    name = "terraform-example-instance"
    
    ingress {
        from_port = var.server_port
        to_port = var.server_port
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

#------------------OUT

output "alb_dns_name" {
    value = aws_lb.example.dns_name
}
