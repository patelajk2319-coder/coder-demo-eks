output "alb_controller_role_arn" {
  description = "IAM role ARN (IRSA) used by the AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}
