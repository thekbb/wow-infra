resource "aws_lb" "nlb" {
  name               = "azerothcore-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for s in aws_subnet.public : s.id]
}

resource "aws_lb_target_group" "auth" {
  name        = "azerothcore-auth"
  port        = var.auth_container_port
  protocol    = "TCP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  preserve_client_ip = true

  health_check {
    protocol = "TCP"
    port     = var.auth_container_port
  }
}

resource "aws_lb_target_group" "world" {
  name        = "azerothcore-world"
  port        = var.world_container_port
  protocol    = "TCP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  preserve_client_ip = true

  health_check {
    protocol = "TCP"
    port     = var.world_container_port
  }
}

resource "aws_lb_listener" "auth" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 3724
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth.arn
  }
}

resource "aws_lb_listener" "world" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 8085
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.world.arn
  }
}
