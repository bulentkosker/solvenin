// ============================================================
// cache.js — Tenant-level sessionStorage cache
// ============================================================
// Backs hot tenant queries (get_my_companies, companies select,
// company_modules, company_users) with a 15-minute TTL so a page
// open in the same session reuses the data instead of round-tripping.
//
// Invalidate on:
//   - logout                    → tenantCache.clear()
//   - switch active company     → tenantCache.clear() (company-scoped keys are stale)
//   - admin updates modules/perm → tenantCache.invalidate('modules.<companyId>')
//
// Keys (convention):
//   tenant.myCompanies            (get_my_companies output)
//   tenant.company.<companyId>    (companies row with subscription/freeze flags)
//   tenant.modules.<companyId>    (company_modules list)
//   tenant.user.<companyId>       (company_users row for current user — role)
// ============================================================

(function(){
  const PREFIX = 'tenant.';
  function k(key){ return PREFIX + key; }
  const DEFAULT_TTL_MIN = 15;

  const inflight = new Map(); // request dedupe within the same tick

  window.tenantCache = {
    get(key, ttlMin = DEFAULT_TTL_MIN) {
      try {
        const raw = sessionStorage.getItem(k(key));
        if (!raw) return null;
        const obj = JSON.parse(raw);
        if (!obj || typeof obj.t !== 'number') return null;
        const ageMs = Date.now() - obj.t;
        if (ageMs > ttlMin * 60000) {
          sessionStorage.removeItem(k(key));
          return null;
        }
        return obj.v;
      } catch(e) { return null; }
    },

    set(key, value) {
      try {
        sessionStorage.setItem(k(key), JSON.stringify({ t: Date.now(), v: value }));
      } catch(e) { /* quota or disabled — silent miss */ }
    },

    invalidate(key) {
      try { sessionStorage.removeItem(k(key)); } catch(e) {}
    },

    clear() {
      try {
        const dead = [];
        for (let i = 0; i < sessionStorage.length; i++) {
          const sk = sessionStorage.key(i);
          if (sk && sk.startsWith(PREFIX)) dead.push(sk);
        }
        dead.forEach(sk => sessionStorage.removeItem(sk));
      } catch(e) {}
    },

    // Cache-aside fetch helper. Returns cached value if fresh, otherwise
    // runs `fetcher()` (an async function) once and stores its result.
    // Concurrent calls for the same key share the same in-flight promise
    // so a page that fires multiple lookups doesn't issue parallel fetches.
    async fetch(key, fetcher, ttlMin = DEFAULT_TTL_MIN) {
      const cached = this.get(key, ttlMin);
      if (cached !== null) return cached;
      if (inflight.has(key)) return inflight.get(key);
      const p = (async () => {
        try {
          const value = await fetcher();
          if (value !== null && value !== undefined) this.set(key, value);
          return value;
        } finally {
          inflight.delete(key);
        }
      })();
      inflight.set(key, p);
      return p;
    },

    // ---- High-level wrappers for the four hot tenant queries ---------
    // Each returns a { data, error } shape so call-sites can drop them
    // into existing destructure patterns: const { data } = await ...

    // get_my_companies — list of companies the user has access to.
    async getMyCompanies(sb) {
      const data = await this.fetch('myCompanies', async () => {
        const r = await sb.rpc('get_my_companies');
        return r.error ? null : r.data;
      });
      return { data, error: data == null ? { message: 'fetch failed' } : null };
    },

    // get_my_account_state — plan/subscription/limits for the current user.
    async getMyAccountState(sb) {
      const data = await this.fetch('accountState', async () => {
        const r = await sb.rpc('get_my_account_state');
        return r.error ? null : r.data;
      });
      return { data, error: data == null ? { message: 'fetch failed' } : null };
    },
  };
})();
