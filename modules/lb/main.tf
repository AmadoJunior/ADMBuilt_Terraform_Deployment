# Load Balancer Security Group
resource "aws_security_group" "lb" {
  name   = "${var.environment}-lb-security-group"
  vpc_id = var.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Load Balancer
resource "aws_lb" "default" {
  name            = "${var.environment}-lb"
  subnets         = var.public_subnets
  security_groups = [aws_security_group.lb.id]
}

# Target Groups
resource "aws_lb_target_group" "client" {
  name        = "${var.environment}-client-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    matcher = 200
    path    = "/index.html"
    port    = 3000
  }
}
resource "aws_lb_target_group" "strapi" {
  name        = "${var.environment}-strapi-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    matcher = 204
    path    = "/_health"
    port    = 1337
  }
}

# LB Listener
resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.default.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.client.arn
    type             = "forward"
  }
}

# API Listener Rule
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.default.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.strapi.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}
