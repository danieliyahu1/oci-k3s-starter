locals {
  # Tagged so you can tell, a year from now, which console resources came from this repo
  # and which you clicked together at 1am. `tofu destroy` only removes what it created;
  # everything else is yours to find by hand.
  tags = {
    managed_by = "opentofu"
    project    = "oci-k3s-starter"
    instance   = var.instance_name
  }

  # The image to boot. A pinned image_ocid wins; otherwise take the newest Canonical
  # Ubuntu the lookup returned.
  # ⚠ NOT just images[0]. If the filter matches nothing — Canonical renames something, or
  # 24.04 leaves your region — `images[0]` is an "index out of range" error that tells you
  # nothing about why. The check below turns that into a sentence naming the cause and the
  # way out.
  ubuntu_images = data.oci_core_images.ubuntu_arm.images
  image_id      = var.image_ocid != null ? var.image_ocid : (length(local.ubuntu_images) > 0 ? local.ubuntu_images[0].id : null)

  # The apps THIS deployment serves, on top of the generic defaults in var.tunnel_routes.
  # Kept here — in tracked code — so a fresh clone reproduces every hostname without a
  # machine-local tfvars. The gitignored tfvars holds only account and secret values
  # (region, OCIDs, tokens, emails); var.tunnel_routes stays as the override for anything
  # unusual. `access = false` serves that hostname publicly, with no Cloudflare Access.
  app_routes = {
    daftari = {
      service       = "http://daftari.daftari.svc.cluster.local:80"
      no_tls_verify = false
      access        = false
    }
    kticket = {
      service       = "http://kticket.kticket.svc.cluster.local:3000"
      no_tls_verify = false
      access        = true
    }
    onepercent = {
      service       = "http://top-one-percent-club.top-one-percent-club.svc.cluster.local:80"
      no_tls_verify = false
      access        = true
    }
    kasodds = {
      service       = "http://kasodds.kasodds.svc.cluster.local:3000"
      no_tls_verify = false
      access        = false
    }
    onlykas = {
      service       = "http://onlykas.onlykas.svc.cluster.local:80"
      no_tls_verify = false
      access        = false
    }
  }

  tunnel_routes = merge(var.tunnel_routes, local.app_routes)
}
