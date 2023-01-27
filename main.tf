terraform {
  //s3 backend defination
  backend "s3" {
    bucket         = "ns-devops-terraform-bucket"
    key            = "web-app/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-locking"
    encrypt        = true
    profile        = "tfadmin"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>4.0"
    }
  }
}

###configuration for the aws provier
provider "aws" {
  region  = "ap-south-1"
  profile = "tfadmin"
}

# # Boolean constraint on whether the desired VPC is the default VPC for the region. Everything is optional
data "aws_vpc" "default_vpc" {
  default = true
}

# ##This resource can be useful for getting back a set of subnet IDs and specified vpc.
data "aws_subnets" "default_subnet" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_vpc.id] #referencing default vpc here
  }
}

###-------------------------------------Setup S3 bucket, versioning and AES256 Encryption----------------------------------#####
resource "aws_s3_bucket" "tf-bucket" {
  bucket_prefix = "exmaple-web-app-data"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.tf-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_crypto_conf" {
  bucket = aws_s3_bucket.tf-bucket.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
###-------------------------------------------------------------------------------------------------------------------------#####


###-------------------------------------SG & SG rule for EC2 instances and EC2 instances creation--------------------------#####
# # Provides a security group resource. All arguments are optional, "name" Name of the security group. 
# # If omitted, Terraform will assign a random, unique name.
resource "aws_security_group" "instances" {
  name = "instance-security-group"
}

# # Provides a security group rule resource. Represents a single ingress or egress group rule,
# #  which can be added to external Security Groups.
resource "aws_security_group_rule" "allow_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.instances.id #binding "aws_security_group" and "aws_security_group_rule"

  //Allow inbound traffic on port 8080
  from_port   = 8080
  to_port     = 8080
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# //AMI: Amazon Linux 2 - Kernel 4.14
# //ami-093613b5938a7e47c 

//Creating http webserver instance_1 and instance_2
resource "aws_instance" "instance_1" {
  ami             = "ami-093613b5938a7e47c"
  instance_type   = "t3.micro"
  security_groups = [aws_security_group.instances.name]
  user_data       = <<-EOF
  #!/bin/bash
  echo "Hello, World 1" > index.html
  python3 -m http.server 8080 &
  EOF
}

resource "aws_instance" "instance_2" {
  ami             = "ami-093613b5938a7e47c"
  instance_type   = "t3.micro"
  security_groups = [aws_security_group.instances.name]
  user_data       = <<-EOF
  #!/bin/bash
  echo "Hello, World 2" > index.html
  python3 -m http.server 8080 &
  EOF
}
###-------------------------------------------------------------------------------------------------------------------------#####



# //"aws_alb_listener" Provides a Load Balancer Listener resource. # default_action - (Required) Configuration block for default actions. Detailed below.
# load_balancer_arn - (Required, Forces New Resource) ARN of the load balancer.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  #By default, return a simple 404[not found] page. type - (Required) Type of routing action. 
  # Valid values are forward, redirect, fixed-response, authenticate-cognito and authenticate-oidc.
  default_action {
    type = "fixed-response"

    # fixed_response - (Optional) Information for creating an action that returns a custom HTTP response. Required if type is fixed-response.
    fixed_response {
      content_type = "text/plain"
      message_body = "404: Page not found"
      status_code  = 400
    }
  }
}


###----------------------------------------lb_target_group & its attachment----------------------------------------------#####
//defining target group for EC2 instances. Provides a Target Group resource for use with Load Balancer resources.
resource "aws_lb_target_group" "instances" {
  name     = "example-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

//Attaching EC2 instance1 to the target group.
resource "aws_lb_target_group_attachment" "instance_1" {
  target_group_arn = aws_lb_target_group.instances.arn
  target_id        = aws_instance.instance_1.id
  port             = 8080
}

//Attaching EC2 instance2 to the target group.
resource "aws_lb_target_group_attachment" "instance_2" {
  target_group_arn = aws_lb_target_group.instances.arn
  target_id        = aws_instance.instance_2.id
  port             = 8080
}

//Create Load Balancer("aws_lb_load_listener" named "http") Listener Rule resource. One or more condition blocks can be set per rule.
resource "aws_lb_listener_rule" "instances" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.instances.arn
  }
}
###-----------------------------------------------------------------------------------------------------------------------------#####


###---------------------------------------SG & SG rules(ingress/egress) for alb------------------------------------------#####
//Creating security group for "alb". SG and SG rule will allow HTTP/80 inbound/ingress access to the alb(application load blancer)
resource "aws_security_group" "alb" {
  name = "alb-security-group"
}

//Security Group "alb" rules creation. 
resource "aws_security_group_rule" "allow_alb_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "allow_alb_http_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
###------------------------------------------------------------------------------------------------------------------------------#####

//Creating Application Load Balancer using subnet ids and above defined security group.
resource "aws_lb" "load_balancer" {
  name               = "web-app-lb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default_subnet.ids
  security_groups    = [aws_security_group.alb.id]
}


//Creating hosted zone and dns record. "aws_route53_zone" Manages a Route53 Hosted Zone. For use in subdomains, note that you need to create a aws_route53_record of type NS as well as the subdomain zone.
resource "aws_route53_zone" "primary" {
  name = "example.com" //Assumed, change accordingly  
}

//"aws_route53_record" Provides a Route53 record resource. TTL for all alias records is 60 seconds, you cannot change this, therefore ttl has to be omitted in alias records.
resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "example.com" //Assumed, change accordingly
  type    = "A"

  alias {
    name                   = aws_lb.load_balancer.dns_name
    zone_id                = aws_lb.load_balancer.zone_id
    evaluate_target_health = true
  }
}

//"aws_db_instance" Provides an RDS instance resource. A DB instance is an isolated database environment in the cloud. A DB instance can contain multiple user-created databases.
resource "aws_db_instance" "db_instance" {
  allocated_storage          = 20
  auto_minor_version_upgrade = true //Risky for prod environment
  storage_type               = "standard"
  engine                     = "postgres"
  engine_version             = "12"
  instance_class             = "db.t2.micro"
  db_name                    = "my_db"
  username                   = "foo"
  password                   = "foobarbaz"
  skip_final_snapshot        = true
}


