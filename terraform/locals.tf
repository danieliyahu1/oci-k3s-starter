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

  # The Cloudflare zone that hosts a custom-domain route (e.g. kasodds.com). Looked up
  # by name so its id is not one more value to copy from the dashboard. Read only when
  # Cloudflare is on, so a rung-1 apply never calls the Cloudflare API.
  kasodds_zone_id = var.enable_cloudflare ? data.cloudflare_zone.kasodds[0].id : null

  # The apps THIS deployment serves, on top of the generic defaults in var.tunnel_routes.
  # Kept here — in tracked code — so a fresh clone reproduces every hostname without a
  # machine-local tfvars. The gitignored tfvars holds only account and secret values
  # (region, OCIDs, tokens, emails); var.tunnel_routes stays as the override for anything
  # unusual. `access = false` serves that hostname publicly, with no Cloudflare Access.
  #
  # `hostname`/`zone_id` carry a route on a domain other than var.domain (kasodds.com);
  # null means the usual `<key>.<var.domain>` in var.cf_zone_id.
  app_routes = {
    daftari = {
      service       = "http://daftari.daftari.svc.cluster.local:80"
      no_tls_verify = false
      access        = false
      hostname      = null
      zone_id       = null
    }
    kticket = {
      service       = "http://kticket.kticket.svc.cluster.local:3000"
      no_tls_verify = false
      access        = false
      hostname      = null
      zone_id       = null
    }
    onepercent = {
      service       = "http://top-one-percent-club.top-one-percent-club.svc.cluster.local:80"
      no_tls_verify = false
      access        = false
      hostname      = null
      zone_id       = null
    }
    kasodds = {
      service       = "http://kasodds.kasodds.svc.cluster.local:3000"
      no_tls_verify = false
      access        = false
      hostname      = "kasodds.com"
      zone_id       = local.kasodds_zone_id
    }
    kasodds_www = {
      service       = "http://kasodds.kasodds.svc.cluster.local:3000"
      no_tls_verify = false
      access        = false
      hostname      = "www.kasodds.com"
      zone_id       = local.kasodds_zone_id
    }
    onlykas = {
      service       = "http://onlykas.onlykas.svc.cluster.local:80"
      no_tls_verify = false
      access        = false
      hostname      = null
      zone_id       = null
    }
  }

  tunnel_routes = merge(var.tunnel_routes, local.app_routes)

  # The old hostnames redirect to the new one — in tracked code; var.redirects overrides.
  # Path and query are preserved, so existing invite links keep working. Both prior names
  # are kept: the original (kaspa-even-odd) and the short-lived rename (kasodds).
  app_redirects = {
    "kaspa-even-odd.danieliyahu.com" = "https://kasodds.com"
    "kasodds.danieliyahu.com"        = "https://kasodds.com"
  }

  redirects = merge(var.redirects, local.app_redirects)
}
