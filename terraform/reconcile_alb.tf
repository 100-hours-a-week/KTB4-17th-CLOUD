# Read-only proposals: never reuse obsolete rule IDs for the current rule.
# Keep the historical root-to-module moved blocks intact.
removed {
  from = module.alb.aws_lb_listener_rule.ws
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.alb.aws_lb_listener_rule.ws_ai_practice
  lifecycle {
    destroy = false
  }
}

import {
  to = module.alb.aws_lb_listener_rule.chat_routes
  id = "arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:listener-rule/app/star23-alb/1ca5051586e3c967/7486e2341aeaa359/a1bcba60b2a96fb8"
}
