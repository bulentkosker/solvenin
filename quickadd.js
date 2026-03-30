/* quickadd.js — Searchable dropdown with inline quick-add for Solvenin ERP
   Usage: QA.create(containerEl, opts) → controller
   opts: { items, value, placeholder, onSelect, onAdd, addLabel }
   items: [{id, name, ...}]  (also accepts {id, label})
   controller: { getValue(), setValue(id), setItems(items), addAndSelect(item) }
*/
window.QA = (function () {
  let _css = false;

  function injectCSS() {
    if (_css) return;
    _css = true;
    const s = document.createElement('style');
    s.textContent = `
      .qa-wrap { position:relative; display:block; }
      .qa-input {
        width:100%; padding:8px 10px; border:1px solid var(--gray200,#e2e8f0);
        border-radius:8px; font-size:13px; color:var(--gray800,#1e293b);
        outline:none; background:#fff; font-family:inherit; cursor:pointer;
        transition:border .15s; box-sizing:border-box;
      }
      .qa-input:focus { border-color:var(--blue,#3b82f6); box-shadow:0 0 0 3px rgba(59,130,246,.1); }
      .qa-panel {
        position:absolute; top:calc(100% + 4px); left:0; right:0;
        background:#fff; border:1px solid var(--gray200,#e2e8f0);
        border-radius:10px; box-shadow:0 8px 24px rgba(0,0,0,.12);
        z-index:1500; max-height:220px; overflow-y:auto; display:none;
      }
      .qa-panel.qa-open { display:block; }
      .qa-opt {
        padding:8px 12px; font-size:13px; color:var(--gray700,#334155);
        cursor:pointer; transition:background .1s; user-select:none;
      }
      .qa-opt:hover, .qa-opt.qa-hl { background:var(--gray50,#f8fafc); }
      .qa-opt.qa-selected { background:var(--blue-light,#eff6ff); color:var(--blue,#3b82f6); font-weight:600; }
      .qa-opt.qa-add-opt { color:var(--blue,#3b82f6); font-weight:600; border-top:1px solid var(--gray100,#f1f5f9); }
      .qa-opt.qa-add-opt:hover { background:var(--blue-light,#eff6ff); }
      .qa-opt.qa-empty { color:var(--gray400,#94a3b8); font-style:italic; cursor:default; }
      .qa-opt.qa-empty:hover { background:transparent; }
    `;
    document.head.appendChild(s);
  }

  function escH(s) {
    return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function escA(s) {
    return String(s ?? '').replace(/"/g, '&quot;');
  }

  function normalizeItems(raw) {
    return (raw || []).map(i => ({
      id: String(i.id ?? ''),
      label: String(i.label ?? i.name ?? ''),
      _raw: i,
    }));
  }

  function create(container, opts) {
    injectCSS();
    container.classList.add('qa-wrap');
    container.innerHTML = `
      <input class="qa-input" type="text" placeholder="${escA(opts.placeholder || 'Ara...')}" autocomplete="off">
      <div class="qa-panel"></div>`;

    const input = container.querySelector('.qa-input');
    const panel = container.querySelector('.qa-panel');

    let items = normalizeItems(opts.items);
    let value = String(opts.value ?? '');
    let isOpen = false;

    function labelOf(id) {
      return items.find(i => i.id === id)?.label ?? '';
    }

    function renderPanel(query) {
      const q = (query || '').toLowerCase().trim();
      const filtered = q ? items.filter(i => i.label.toLowerCase().includes(q)) : items;

      let html = filtered.map(i =>
        `<div class="qa-opt${i.id === value ? ' qa-selected' : ''}" data-id="${escA(i.id)}">${escH(i.label)}</div>`
      ).join('');

      if (!filtered.length) {
        html = `<div class="qa-opt qa-empty">${window.t ? window.t('lbl_none') : 'Sonuç yok'}</div>`;
      }

      if (opts.onAdd && q) {
        const addTxt = opts.addLabel ? opts.addLabel(query) : `+ "${query}" ekle`;
        html += `<div class="qa-opt qa-add-opt" data-id="__add__">${escH(addTxt)}</div>`;
      }

      panel.innerHTML = html;
    }

    function open() {
      renderPanel('');
      panel.classList.add('qa-open');
      isOpen = true;
      input.select();
    }

    function close(resetText) {
      panel.classList.remove('qa-open');
      isOpen = false;
      if (resetText !== false) input.value = labelOf(value);
    }

    function selectById(id) {
      value = id || '';
      input.value = labelOf(value);
      close(false);
    }

    // Input events
    input.addEventListener('focus', () => {
      input.value = '';
      open();
    });
    input.addEventListener('input', () => {
      renderPanel(input.value);
      if (!isOpen) { panel.classList.add('qa-open'); isOpen = true; }
    });
    input.addEventListener('keydown', e => {
      if (e.key === 'Escape') { close(); return; }
      if (!isOpen) return;
      const opts_list = panel.querySelectorAll('.qa-opt:not(.qa-empty)');
      if (!opts_list.length) return;
      let idx = [...opts_list].findIndex(o => o.classList.contains('qa-hl'));
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        idx = idx < opts_list.length - 1 ? idx + 1 : 0;
        opts_list.forEach(o => o.classList.remove('qa-hl'));
        opts_list[idx].classList.add('qa-hl');
        opts_list[idx].scrollIntoView({ block: 'nearest' });
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        idx = idx > 0 ? idx - 1 : opts_list.length - 1;
        opts_list.forEach(o => o.classList.remove('qa-hl'));
        opts_list[idx].classList.add('qa-hl');
        opts_list[idx].scrollIntoView({ block: 'nearest' });
      } else if (e.key === 'Enter') {
        e.preventDefault();
        const hl = panel.querySelector('.qa-opt.qa-hl');
        if (hl) hl.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
      }
    });
    input.addEventListener('blur', () => {
      // Delay so panel click can fire first
      setTimeout(() => close(), 150);
    });

    // Panel click
    panel.addEventListener('mousedown', e => {
      const opt = e.target.closest('.qa-opt');
      if (!opt || opt.classList.contains('qa-empty')) return;
      e.preventDefault();
      const id = opt.dataset.id;
      if (id === '__add__') {
        const query = input.value.trim();
        close();
        if (opts.onAdd) opts.onAdd(query);
        return;
      }
      selectById(id);
      const item = items.find(i => i.id === id);
      if (opts.onSelect) opts.onSelect(id, item?._raw);
    });

    // Close on outside click
    document.addEventListener('click', e => {
      if (isOpen && !container.contains(e.target)) close();
    }, true);

    // Set initial display
    if (value) input.value = labelOf(value);

    const ctrl = {
      getValue() { return value; },
      setValue(id) { selectById(String(id ?? '')); },
      setItems(raw) {
        items = normalizeItems(raw);
        input.value = labelOf(value);
      },
      addAndSelect(item) {
        const normalized = { id: String(item.id ?? ''), label: String(item.label ?? item.name ?? ''), _raw: item };
        items.push(normalized);
        selectById(normalized.id);
        if (opts.onSelect) opts.onSelect(normalized.id, item);
      },
    };

    container._qa = ctrl;
    return ctrl;
  }

  return { create, escH };
})();
