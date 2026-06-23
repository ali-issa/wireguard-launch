locals {
  az = coalesce(var.availability_zone, "${var.region}a")

  # Default user-data is the repo's bootstrap stub, which fetches and runs the
  # full launch script on first boot (stays under Lightsail's 16 KB limit).
  user_data = coalesce(var.user_data, file("${path.module}/../bootstrap.sh"))
}

resource "aws_lightsail_key_pair" "wg" {
  count      = var.ssh_public_key == null ? 0 : 1
  name       = "${var.name}-key"
  public_key = var.ssh_public_key
}

resource "aws_lightsail_instance" "wg" {
  name              = var.name
  availability_zone = local.az
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  user_data         = local.user_data
  key_pair_name     = var.ssh_public_key == null ? null : aws_lightsail_key_pair.wg[0].name
  tags              = var.tags
}

# Stable endpoint so client configs don't break when the instance stops/starts.
resource "aws_lightsail_static_ip" "wg" {
  name = "${var.name}-ip"
}

resource "aws_lightsail_static_ip_attachment" "wg" {
  static_ip_name = aws_lightsail_static_ip.wg.name
  instance_name  = aws_lightsail_instance.wg.name
}

# Firewall. This resource is authoritative: it manages the full set of public
# ports, so it also closes anything Lightsail opened by default.
resource "aws_lightsail_instance_public_ports" "wg" {
  instance_name = aws_lightsail_instance.wg.name

  # WireGuard — reachable from anywhere (clients roam between networks).
  port_info {
    protocol  = "udp"
    from_port = var.wg_port
    to_port   = var.wg_port
  }

  # SSH
  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = var.ssh_allowed_cidrs
  }

  # Web portal: 80 (HTTP->HTTPS redirect / future ACME) and 443 (HTTPS).
  dynamic "port_info" {
    for_each = var.enable_portal_port ? toset([80, 443]) : toset([])
    iterator = p
    content {
      protocol  = "tcp"
      from_port = p.value
      to_port   = p.value
      cidrs     = var.portal_allowed_cidrs
    }
  }
}
