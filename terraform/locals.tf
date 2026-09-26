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

  # The Cloudflare zones that host custom-domain routes (kasodds.com, kaskama.com).
  # onlykas.app is still resolved because it remains a redirect zone for the old
  # hostname, even though it no longer serves the application.
  # Looked up by name so their ids are not one more value to copy from the dashboard.
  # Read only when Cloudflare is on, so a rung-1 apply never calls the Cloudflare API.
  kasodds_zone_id = var.enable_cloudflare ? data.cloudflare_zone.kasodds[0].id : null
  kaskama_zone_id = var.enable_cloudflare ? data.cloudflare_zone.kaskama[0].id : null
  onlykas_zone_id = var.enable_cloudflare ? data.cloudflare_zone.onlykas[0].id : null

  # The apps THIS deployment serves, on top of the generic defaults in var.tunnel_routes.
  # Kept here — in tracked code — so a fresh clone reproduces every hostname without a
  # machine-local tfvars. The gitignored tfvars holds only account and secret values
  # (region, OCIDs, tokens, emails); var.tunnel_routes stays as the override for anything
  # unusual. `access = false` serves that hostname publicly, with no Cloudflare Access.
  #
  # `hostname`/`zone_id` carry a route on a domain other than var.domain (kasodds.com,
  # kaskama.com); null means the usual `<key>.<var.domain>` in var.cf_zone_id.
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
    kaskama = {
      service       = "http://kaskama.kaskama.svc.cluster.local:80"
      no_tls_verify = false
      access        = false
      hostname      = "kaskama.com"
      zone_id       = local.kaskama_zone_id
    }
  }

  tunnel_routes = merge(var.tunnel_routes, local.app_routes)

  # Every hostname that is NOT the one true origin redirects to it — in tracked code;
  # var.redirects overrides. Path and query are preserved, so existing invite links keep
  # working. An app serves on ONE hostname: the apex. `www.` is not a second copy of the
  # site, it is a redirect — otherwise the browser sees two origins, the session cookie
  # (SameSite=strict, host-scoped) does not cross between them, and any backend that pins
  # the allowed Origin to a single value rejects the other one outright.
  #
  # `zone_id` names the Cloudflare zone that answers for the SOURCE host: null is the
  # primary zone (var.cf_zone_id), a value carries a redirect whose source lives in a
  # different domain (www.kaskama.com, www.onlykas.app, www.kasodds.com).
  app_redirects = {
    "kaspa-even-odd.danieliyahu.com" = { target = "https://kasodds.com", zone_id = null }
    "onlykas.danieliyahu.com"        = { target = "https://kaskama.com", zone_id = null }
    "onlykas.app"                    = { target = "https://kaskama.com", zone_id = local.onlykas_zone_id }
    "www.kasodds.com"                = { target = "https://kasodds.com", zone_id = local.kasodds_zone_id }
    "www.kaskama.com"                = { target = "https://kaskama.com", zone_id = local.kaskama_zone_id }
    "www.onlykas.app"                = { target = "https://kaskama.com", zone_id = local.onlykas_zone_id }
  }

  # var.redirects stays a plain source => target map and always means the primary zone, so
  # the common case needs no zone. Normalise it, then let local.app_redirects win.
  redirects = merge(
    { for host, target in var.redirects : host => { target = target, zone_id = null } },
    local.app_redirects,
  )

  # A zone-level ruleset belongs to exactly one zone, so the redirects are split by the zone
  # that answers for them. The primary zone keeps its own resource address — the one every
  # apply has used — and each other zone gets one ruleset of its own.
  redirects_primary = {
    for host, r in local.redirects : host => r.target if r.zone_id == null
  }
  redirects_custom = {
    for zone_id in toset([for _, r in local.redirects : r.zone_id if r.zone_id != null]) :
    zone_id => {
      for host, r in local.redirects : host => r.target if r.zone_id == zone_id
    }
  }

  # One redirect rule shape, keyed by source host, so both rulesets emit identical JSON.
  redirect_rules = {
    for host, r in local.redirects : host => {
      # `ref` gives the rule a stable id, so editing the expression updates the rule
      # instead of recreating it.
      ref         = "redirect_${replace(host, ".", "_")}"
      description = "Redirect ${host} to ${r.target}"
      expression  = "http.host eq \"${host}\""
      action      = "redirect"

      action_parameters = {
        from_value = {
          status_code = 301
          # concat, not a bare URL: a static target would drop the path. This sends
          # /anything on the old host to /anything on the new one.
          target_url = {
            expression = "concat(\"${r.target}\", http.request.uri.path)"
          }
          preserve_query_string = true
        }
      }
    }
  }
}
