#output "scoobychat_server_ip" {
#  value = aws_instance.scoobychat_server[0].public_ip
#}

output "scoobychat_server_spot_ip" {
  value = aws_spot_instance_request.test_worker[0].public_ip
}
