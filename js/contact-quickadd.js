/**
 * Contact quick-add modal — single reusable helper for every page that
 * lets the user type a name into a QA picker and create a new contact
 * without leaving the flow.
 *
 * Usage:
 *   ContactQuickAdd.open({
 *     initialName: 'ABC Ltd',
 *     typeHint: 'customer' | 'supplier' | 'both',  // drives is_customer / is_supplier
 *     onCreated(contact) { ... }                    // { id, name, ... } from the insert
 *   });
 *
 * The modal DOM is injected lazily on first open, so every page that
 * <script src="js/contact-quickadd.js"> gets the same markup and behavior.
 * Requires window.sb (Supabase client), window.companyId, and utils.js
 * (submitting / getErrorMessage / showToast when available).
 */
(function () {
  'use strict';
  if (window.ContactQuickAdd) return;

  const MODAL_ID = 'contact-quickadd-modal';
  let state = null; // { typeHint, onCreated }

  function ensureModal() {
    if (document.getElementById(MODAL_ID)) return;
    const wrap = document.createElement('div');
    wrap.innerHTML = `
<div class="modal-overlay" id="${MODAL_ID}" style="z-index:2500">
  <div class="modal" style="max-width:420px">
    <div class="modal-header">
      <div class="modal-title">Yeni Cari Ekle</div>
      <button class="modal-close" onclick="ContactQuickAdd.close()">✕</button>
    </div>
    <div class="modal-body">
      <div class="form-group">
        <label>İsim *</label>
        <input type="text" id="cqa-name" style="width:100%;padding:9px 12px;border:1px solid var(--gray200);border-radius:10px;font-size:13px;outline:none">
      </div>
      <div class="form-group">
        <label>Tip</label>
        <div style="display:flex;gap:8px">
          <label style="flex:1;display:flex;align-items:center;gap:6px;padding:8px 10px;border:1px solid var(--gray200);border-radius:10px;cursor:pointer;font-size:13px">
            <input type="radio" name="cqa-type" value="customer"> Müşteri
          </label>
          <label style="flex:1;display:flex;align-items:center;gap:6px;padding:8px 10px;border:1px solid var(--gray200);border-radius:10px;cursor:pointer;font-size:13px">
            <input type="radio" name="cqa-type" value="supplier"> Tedarikçi
          </label>
          <label style="flex:1;display:flex;align-items:center;gap:6px;padding:8px 10px;border:1px solid var(--gray200);border-radius:10px;cursor:pointer;font-size:13px">
            <input type="radio" name="cqa-type" value="both"> Her İkisi
          </label>
        </div>
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
        <div class="form-group">
          <label>Email</label>
          <input type="email" id="cqa-email" style="width:100%;padding:9px 12px;border:1px solid var(--gray200);border-radius:10px;font-size:13px;outline:none">
        </div>
        <div class="form-group">
          <label>Telefon</label>
          <input type="tel" id="cqa-phone" style="width:100%;padding:9px 12px;border:1px solid var(--gray200);border-radius:10px;font-size:13px;outline:none">
        </div>
      </div>
      <div class="form-group">
        <label>Vergi No / BIN</label>
        <input type="text" id="cqa-tax" style="width:100%;padding:9px 12px;border:1px solid var(--gray200);border-radius:10px;font-size:13px;outline:none">
      </div>
    </div>
    <div class="modal-footer">
      <button class="btn btn-outline" onclick="ContactQuickAdd.close()">İptal</button>
      <button class="btn btn-primary" onclick="ContactQuickAdd.save()" data-action="save">Ekle</button>
    </div>
  </div>
</div>`;
    document.body.appendChild(wrap.firstElementChild);
  }

  function open({ initialName = '', typeHint = 'customer', onCreated } = {}) {
    ensureModal();
    state = { typeHint, onCreated };
    document.getElementById('cqa-name').value = initialName;
    document.getElementById('cqa-email').value = '';
    document.getElementById('cqa-phone').value = '';
    document.getElementById('cqa-tax').value = '';
    const t = typeHint === 'supplier' ? 'supplier' : typeHint === 'both' ? 'both' : 'customer';
    document.querySelectorAll('input[name="cqa-type"]').forEach(r => { r.checked = r.value === t; });
    document.getElementById(MODAL_ID).classList.add('open');
    setTimeout(() => document.getElementById('cqa-name').focus(), 50);
  }

  function close() {
    const el = document.getElementById(MODAL_ID);
    if (el) el.classList.remove('open');
    state = null;
  }

  async function save() {
    // Reuse the global double-submit guard when utils.js is present.
    const guarded = typeof window.submitting === 'function';
    if (guarded && window.submitting()) return;
    try {
      const name = document.getElementById('cqa-name').value.trim();
      if (!name) {
        (window.showToast || window.alert)('İsim zorunlu', 'error');
        return;
      }
      const selected = document.querySelector('input[name="cqa-type"]:checked')?.value || 'customer';
      const is_customer = selected === 'customer' || selected === 'both';
      const is_supplier = selected === 'supplier' || selected === 'both';
      const row = {
        company_id: window.companyId,
        name,
        email: document.getElementById('cqa-email').value.trim() || null,
        phone: document.getElementById('cqa-phone').value.trim() || null,
        tax_number: document.getElementById('cqa-tax').value.trim() || null,
        is_customer, is_supplier,
        type: is_customer && is_supplier ? 'customer' : (is_supplier ? 'supplier' : 'customer'),
        is_active: true
      };
      const { data, error } = await window.sb.from('contacts').insert(row).select().single();
      if (error) {
        const msg = window.getErrorMessage ? window.getErrorMessage(error) : error.message;
        (window.showToast || window.alert)(msg, 'error');
        return;
      }
      (window.showToast || console.log)('Cari eklendi ✓', 'success');
      const cb = state?.onCreated;
      close();
      if (cb) cb(data);
    } finally {
      if (guarded && window.submitting.reset) window.submitting.reset();
    }
  }

  window.ContactQuickAdd = { open, close, save };
})();
