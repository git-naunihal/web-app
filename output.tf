output "instance1_ip_addr" {
  value = aws_instance.instance_1.public_ip
}

output "instance2_ip_addr" {
  value = aws_instance.instance_2.public_ip
}
output "web-app-lb" {
  value = aws_lb.load_balancer.dns_name
}
output "aws_postgre_instance_endpoint" {
  value = aws_db_instance.db_instance.endpoint
}
output "aws_s3_bucket_tf-bucket" {
  value = aws_s3_bucket.tf-bucket.bucket_domain_name
}