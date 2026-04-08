/* feature-flags.js — Solvenin runtime feature toggles
   Include AFTER the supabase-js script and BEFORE page-specific code.
   Reads the public feature_flags table (RLS allows SELECT for all).
*/
(function () {
  const FeatureFlags = {
    _flags: {},          // flag_name -> evaluated boolean for current user
    _raw: {},            // flag_name -> full row (for app_version, descriptions, etc.)
    _loaded: false,
    _loading: null,

    /**
     * Load and evaluate all flags for the current user/company/plan.
     * Safe to call multiple times — only fetches once unless reset() is called.
     */
    async load(companyId, plan) {
      if (this._loaded) return;
      if (this._loading) return this._loading;

      this._loading = (async () => {
        try {
          // Try to find a supabase client — pages may store it as window._supabase
          // or create their own with the publishable key.
          let sb = window._supabase;
          if (!sb && window.supabase && window.supabase.createClient) {
            sb = window.supabase.createClient(
              'https://jaakjdzpdizjbzvbtcld.supabase.co',
              'sb_publishable_Zp3NcrPr7yPrL8zgpiNmfA_YF7RGHe9'
            );
          }
          if (!sb) { console.warn('[FeatureFlags] no supabase client'); this._loaded = true; return; }

          const { data, error } = await sb.from('feature_flags').select('*');
          if (error) { console.warn('[FeatureFlags] load error:', error.message); this._loaded = true; return; }

          (data || []).forEach((flag) => {
            this._raw[flag.flag_name] = flag;
            this._flags[flag.flag_name] = this._isEnabled(flag, companyId, plan);
          });
          this._loaded = true;
        } catch (e) {
          console.warn('[FeatureFlags] unexpected error:', e);
          this._loaded = true;
        }
      })();
      return this._loading;
    },

    _isEnabled(flag, companyId, plan) {
      if (!flag) return false;
      // 1. Global toggle wins
      if (flag.is_enabled_globally) return true;
      // 2. Per-company allowlist
      if (companyId && Array.isArray(flag.enabled_for_companies) && flag.enabled_for_companies.includes(companyId)) {
        return true;
      }
      // 3. Per-plan allowlist
      if (plan && Array.isArray(flag.enabled_for_plans) && flag.enabled_for_plans.includes(plan)) {
        return true;
      }
      // 4. Stable rollout bucket based on company id
      if (flag.rollout_percentage > 0 && companyId) {
        const bucket = this._hashBucket(companyId);
        if (bucket < flag.rollout_percentage) return true;
      }
      return false;
    },

    /**
     * Cheap deterministic 0-99 bucket from a UUID-ish string.
     * Same companyId always lands in the same bucket so rollout is sticky.
     */
    _hashBucket(s) {
      let h = 0;
      for (let i = 0; i < s.length; i++) {
        h = (h * 31 + s.charCodeAt(i)) >>> 0;
      }
      return h % 100;
    },

    isEnabled(flagName) {
      return this._flags[flagName] === true;
    },

    /** Returns the raw flag row (useful for app_version which lives in `description`) */
    raw(flagName) {
      return this._raw[flagName] || null;
    },

    /** Convenience: read app_version stored in the special row */
    appVersion() {
      const row = this._raw['app_version'];
      return row ? (row.description || '1.0.0') : '1.0.0';
    },

    reset() {
      this._flags = {};
      this._raw = {};
      this._loaded = false;
      this._loading = null;
    },

    /**
     * Maintenance gate: checks the maintenance_mode flag right after load
     * and redirects the user to /maintenance.html if it's on.
     * Pass {skip:true} from the maintenance page itself to avoid loops.
     */
    maintenanceGate({ skip = false } = {}) {
      if (skip) return;
      if (this.isEnabled('maintenance_mode')) {
        try {
          const here = window.location.pathname;
          // Don't redirect away from the lock page itself, the health
          // page, the auth page (admins need to log in to disable), or
          // the service panel (admins disable the flag from there).
          if (!here.endsWith('/system-maintenance.html')
              && !here.endsWith('/health.html')
              && !here.endsWith('/auth.html')
              && !here.endsWith('/service-panel.html')) {
            window.location.replace('system-maintenance.html');
          }
        } catch (e) {}
      }
    },
  };

  // Expose globally
  window.FeatureFlags = FeatureFlags;

  // Convenience auto-loader: pages can call FeatureFlags.load(companyId, plan)
  // explicitly, but we also kick off a no-arg load on DOMContentLoaded so
  // global flags (like maintenance_mode) work even on pages that never call
  // load() themselves.
  function autoLoad() {
    let companyId = null;
    try { companyId = localStorage.getItem('currentCompanyId') || null; } catch (e) {}
    FeatureFlags.load(companyId, null).then(() => {
      FeatureFlags.maintenanceGate();
    });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', autoLoad);
  } else {
    autoLoad();
  }
})();
