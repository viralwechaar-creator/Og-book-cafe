// AUZlabs platform — tenant resolution for static pages.
// DRAFT: not wired into config.js or any live page. Requires the
// tenants/tenant_settings tables in supabase/multi-tenant-schema.sql.
//
// Every static page (index.html, site.html, i.html, order.html) currently
// gets its Supabase project + branding from config.js, which is one
// hardcoded pair of {url, key} per deployed client. Under one shared
// Supabase project, config.js's {url, key} become the same for every
// tenant, and *this* file replaces "which restaurant is this" — resolved
// from the subdomain, per the extraction brief's pattern — instead of
// "which Supabase project did this static build point at".
//
// Usage (replaces reading defaults out of cfg() in index.html today):
//   <script src=/config.js></script>
//   <script src=/tenant.js></script>
//   <script>
//     const sb = supabase.createClient(CFG.url, CFG.key);
//     const tenant = await resolveTenant(sb);
//     // tenant.id, tenant.slug, tenant.name,
//     // tenant.branding / tenant.features / tenant.business_rules
//   </script>

async function resolveTenant(sb) {
  const slug = window.location.hostname.split('.')[0];

  const { data: tenant, error: tErr } = await sb
    .from('tenants')
    .select('id, slug, name, status')
    .eq('slug', slug)
    .single();

  if (tErr || !tenant) return { error: 'not_found', slug };
  if (tenant.status === 'suspended' || tenant.status === 'cancelled') {
    return { error: tenant.status, slug, tenant };
  }

  const { data: settings } = await sb
    .from('tenant_settings')
    .select('branding, features, business_rules')
    .eq('tenant_id', tenant.id)
    .single();

  return {
    id: tenant.id,
    slug: tenant.slug,
    name: tenant.name,
    branding: (settings && settings.branding) || {},
    features: (settings && settings.features) || {},
    business_rules: (settings && settings.business_rules) || {},
  };
}

// Renders the same "not available" state every page should show for a
// missing/suspended/cancelled tenant, instead of each page inventing its
// own. Call this right after resolveTenant() when tenant.error is set.
function renderTenantError(tenant) {
  const msg = {
    not_found: "This page isn't connected to a restaurant yet.",
    suspended: 'This restaurant’s account is currently paused.',
    cancelled: 'This restaurant is no longer using AUZlabs.',
  }[tenant.error] || 'This page is unavailable right now.';
  document.body.innerHTML =
    '<div style="max-width:420px;margin:20vh auto;padding:0 24px;font:15px/1.6 system-ui,sans-serif;text-align:center;color:#444">' +
    msg + '</div>';
}
