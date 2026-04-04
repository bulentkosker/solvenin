/**
 * Solvenin Permission System
 * Include this script in all module pages AFTER supabase client init.
 *
 * Usage:
 *   <script src="permissions.js"></script>
 *   // In init():
 *   const perms = await loadPermissions('inventory');
 *   applyPermissions(perms);
 */

(function() {
  'use strict';

  const FULL_ACCESS = { can_view: true, can_create: true, can_edit: true, can_delete: true };

  /**
   * Load permissions for a specific module.
   * Owner/admin always get full access without DB query.
   */
  async function loadPermissions(module) {
    const sb = window._supabase || window.supabase;
    if (!sb || !sb.auth) return FULL_ACCESS;

    const companyId = localStorage.getItem('currentCompanyId');
    if (!companyId) return FULL_ACCESS;

    const { data: { session } } = await sb.auth.getSession();
    if (!session) return FULL_ACCESS;
    const userId = session.user.id;

    // Check role first — owner/admin skip permission table
    const { data: cu } = await sb.from('company_users')
      .select('role')
      .eq('company_id', companyId)
      .eq('user_id', userId)
      .single();

    if (!cu) return FULL_ACCESS;
    if (cu.role === 'owner' || cu.role === 'admin') return FULL_ACCESS;

    // Fetch module permission
    const { data: perm } = await sb.from('user_permissions')
      .select('can_view, can_create, can_edit, can_delete')
      .eq('company_id', companyId)
      .eq('user_id', userId)
      .eq('module', module)
      .single();

    return perm || { can_view: true, can_create: false, can_edit: false, can_delete: false };
  }

  /**
   * Apply permissions to the page UI.
   * Hides/disables elements based on permission flags.
   */
  function applyPermissions(perms) {
    if (!perms) return;

    // No view access — show access denied overlay
    if (!perms.can_view) {
      const main = document.querySelector('.main-content') || document.querySelector('main') || document.body;
      const overlay = document.createElement('div');
      overlay.style.cssText = 'position:fixed;inset:0;z-index:500;background:#fff;display:flex;align-items:center;justify-content:center;flex-direction:column;gap:12px;padding:40px';
      overlay.innerHTML = `
        <div style="font-size:48px">🔒</div>
        <div style="font-size:18px;font-weight:700;color:#334155">${window.t?.('perm_no_access') || 'Access Denied'}</div>
        <div style="font-size:14px;color:#64748b">${window.t?.('perm_no_access_desc') || 'You do not have permission to view this module.'}</div>
        <a href="dashboard.html" style="margin-top:12px;padding:10px 20px;background:#1e40af;color:#fff;border-radius:10px;text-decoration:none;font-weight:600;font-size:13px">${window.t?.('btn_back_dashboard') || 'Back to Dashboard'}</a>
      `;
      main.style.position = 'relative';
      main.appendChild(overlay);
      return;
    }

    // Hide create buttons
    if (!perms.can_create) {
      document.querySelectorAll('[data-perm="create"], .btn-add, [onclick*="openAdd"], [onclick*="openNew"], [onclick*="Modal()"]').forEach(el => {
        if (el.textContent.includes('+') || el.textContent.includes('Add') || el.textContent.includes('New') || el.textContent.includes('Ekle') || el.textContent.includes('Yeni')) {
          el.style.display = 'none';
        }
      });
    }

    // Hide edit buttons
    if (!perms.can_edit) {
      document.querySelectorAll('[data-perm="edit"], .btn-edit, [onclick*="edit"], [onclick*="Edit"]').forEach(el => {
        el.style.display = 'none';
      });
    }

    // Hide delete buttons
    if (!perms.can_delete) {
      document.querySelectorAll('[data-perm="delete"], .btn-delete, .btn-danger, [onclick*="delete"], [onclick*="Delete"], [onclick*="remove"]').forEach(el => {
        el.style.display = 'none';
      });
    }
  }

  /**
   * Load all permissions for current user (for sidebar use).
   */
  async function loadAllPermissions() {
    const sb = window._supabase || window.supabase;
    if (!sb || !sb.auth) return {};

    const companyId = localStorage.getItem('currentCompanyId');
    if (!companyId) return {};

    const { data: { session } } = await sb.auth.getSession();
    if (!session) return {};
    const userId = session.user.id;

    // Owner/admin → full access to everything
    const { data: cu } = await sb.from('company_users')
      .select('role')
      .eq('company_id', companyId)
      .eq('user_id', userId)
      .single();

    if (!cu || cu.role === 'owner' || cu.role === 'admin') return {};

    const { data: perms } = await sb.from('user_permissions')
      .select('module, can_view, can_create, can_edit, can_delete')
      .eq('company_id', companyId)
      .eq('user_id', userId);

    const map = {};
    (perms || []).forEach(p => { map[p.module] = p; });
    return map;
  }

  // Expose globally
  window.loadPermissions = loadPermissions;
  window.applyPermissions = applyPermissions;
  window.loadAllPermissions = loadAllPermissions;
})();
