output "public_ip" {
  description = "Static public IP of the WireGuard server."
  value       = aws_lightsail_static_ip.wg.ip_address
}

output "instance_name" {
  description = "Lightsail instance name."
  value       = aws_lightsail_instance.wg.name
}

output "ssh_command" {
  description = "SSH into the box (Debian Lightsail's default user is 'admin')."
  value       = "ssh admin@${aws_lightsail_static_ip.wg.ip_address}"
}

output "portal_url" {
  description = "Web portal URL (if enabled)."
  value       = var.enable_portal_port ? "https://${aws_lightsail_static_ip.wg.ip_address}/" : "disabled"
}

output "next_steps" {
  description = "What to do after apply."
  value       = <<-EOT
    1. Wait ~2 min for first boot (cloud-init runs bootstrap.sh -> lightsail-launch.sh).
    2. Portal password:
         ssh admin@${aws_lightsail_static_ip.wg.ip_address} 'sudo cat /root/wg-portal-credentials.txt'
    3. Add a client:
         ssh admin@${aws_lightsail_static_ip.wg.ip_address} 'sudo wg-manage add my-phone'
  EOT
}
