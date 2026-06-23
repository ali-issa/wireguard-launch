# OpenTofu module — Lightsail provisioning

Provisions the cloud side declaratively so you don't click around the console:

- a Lightsail instance (Debian, 512 MB `nano_2_0`) booting `../bootstrap.sh` as
  user-data — which fetches and runs the full launch script on first boot;
- a **static IP** (stable WireGuard endpoint);
- the **firewall** — UDP `51820` (WireGuard), TCP `22` (SSH), TCP `80/443`
  (portal). This is the step that's otherwise manual and easy to forget.

Works with `tofu` (OpenTofu) or `terraform` — the config is identical.

## Prerequisites

- [OpenTofu](https://opentofu.org) ≥ 1.6 (`tofu`) — or Terraform.
- AWS credentials with Lightsail permissions (`AWS_PROFILE=…` or
  `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`).

## Use

```bash
cd opentofu
cp terraform.tfvars.example terraform.tfvars   # edit: region, SSH key, allowed IPs
tofu init
tofu plan
tofu apply
```

`tofu output` then prints the public IP, SSH command, portal URL, and next steps.

> Verify the OS/size IDs for your account once — they occasionally vary by region:
> ```bash
> aws lightsail get-blueprints --query "blueprints[?group=='debian'].[blueprintId,name]" --output table
> aws lightsail get-bundles    --query "bundles[].[bundleId,ramSizeInGb,price]" --output table
> ```
> Override with `-var blueprint_id=… -var bundle_id=…` if needed.

## Inputs (highlights)

| Variable | Default | Notes |
|---|---|---|
| `region` | `eu-west-2` | AWS region |
| `bundle_id` | `nano_2_0` | 512 MB tier |
| `blueprint_id` | `debian_12` | OS image |
| `ssh_public_key` | `null` | install your key; else Lightsail's default |
| `ssh_allowed_cidrs` | `["0.0.0.0/0"]` | **lock to your IP** for safety |
| `enable_portal_port` | `true` | open 80/443 for the portal |
| `wg_port` | `51820` | must match the launch script |

## Notes

- **This creates a *new* instance.** To manage an instance you already made by
  hand, import it instead of applying onto it:
  ```bash
  tofu import aws_lightsail_instance.wg <your-instance-name>
  tofu import aws_lightsail_static_ip.wg <your-static-ip-name>
  ```
- State contains resource metadata (not secrets — keys/passwords are generated
  on the instance). For team use, configure a remote backend (e.g. S3).
- Teardown: `tofu destroy` (then run `uninstall.sh` only matters if you keep the box).
