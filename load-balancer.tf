resource "aws_lb" "nlb" {
  count                            = var.deep_sleep_mode ? 0 : 1
  name                             = "azerothcore-nlb"
  internal                         = false
  load_balancer_type               = "network"
  enable_cross_zone_load_balancing = true
  subnets                          = [for s in aws_subnet.public : s.id]
}

resource "aws_lb_target_group" "auth" {
  count       = var.deep_sleep_mode ? 0 : 1
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
  count       = var.deep_sleep_mode ? 0 : 1
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
  count             = var.deep_sleep_mode ? 0 : 1
  load_balancer_arn = aws_lb.nlb[0].arn
  port              = 3724
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth[0].arn
  }
}

resource "aws_lb_listener" "world" {
  count             = var.deep_sleep_mode ? 0 : 1
  load_balancer_arn = aws_lb.nlb[0].arn
  port              = 8085
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.world[0].arn
  }
}
