# ══════════════════════════════════════════════════════════════════════════════════
#  The SSH endpoint, written where local tooling can read it.
#
#  scripts/connect.* and scripts/k9s.* need the box's address. They must not hardcode it
#  — it is ephemeral, and a copy would silently go stale on a rebuild — and they must not
#  parse local state, which is a second source of truth. So Terraform, the one owner of
#  the address, writes it here on every apply and the scripts read this file.
#
#  Generated, gitignored, never edited by hand. The scripts share one resolver —
#  scripts/ssh-endpoint.ps1 / scripts/ssh-endpoint.sh — which reads this file and falls
#  back to `tofu output` when it is absent.
# ══════════════════════════════════════════════════════════════════════════════════

resource "local_file" "ssh_endpoint" {
  filename = "${path.module}/../.ssh-endpoint"
  content  = oci_core_instance.main.public_ip

  # Owner-only (ignored on Windows). The address is not a secret, but a world-writable
  # file is not worth the default.
  file_permission = "0600"
}
