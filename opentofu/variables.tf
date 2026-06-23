variable "region" {
  description = "AWS region for the Lightsail instance."
  type        = string
  default     = "eu-west-2"
}

variable "availability_zone" {
  description = "Lightsail availability zone. Defaults to <region>a (e.g. eu-west-2a)."
  type        = string
  default     = null
}

variable "name" {
  description = "Base name for the instance and its related resources."
  type        = string
  default     = "wireguard"
}

variable "blueprint_id" {
  description = "Lightsail OS blueprint. Verify with: aws lightsail get-blueprints"
  type        = string
  default     = "debian_12"
}

variable "bundle_id" {
  description = "Lightsail bundle (size). nano_2_0 = 512 MB RAM. List: aws lightsail get-bundles"
  type        = string
  default     = "nano_2_0"
}

variable "ssh_public_key" {
  description = "SSH public key to install. If null, Lightsail's default region key is used."
  type        = string
  default     = null
}

variable "wg_port" {
  description = "WireGuard UDP port. Must match WG_LISTEN_PORT in the launch script."
  type        = number
  default     = 51820
}

variable "enable_portal_port" {
  description = "Open TCP 80/443 for the web portal (HTTP redirect + HTTPS)."
  type        = bool
  default     = true
}

variable "ssh_allowed_cidrs" {
  description = "Source CIDRs allowed to reach SSH (port 22). Lock to your IP for safety."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "portal_allowed_cidrs" {
  description = "Source CIDRs allowed to reach the portal (ports 80/443)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "user_data" {
  description = "Cloud-init user-data. Defaults to the repo's bootstrap.sh (<16 KB)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the Lightsail instance."
  type        = map(string)
  default     = {}
}
