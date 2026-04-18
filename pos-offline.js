/* pos-offline.js — IndexedDB queue + connectivity for offline-first POS
   Include AFTER feature-flags.js and supabase, BEFORE pos.html script.
   Exposes window.PosOfflineDB / PosConnectivity / PosSync /
   completeSaleOfflineFirst().
*/
(function () {
  const PosOfflineDB = {
    db: null,
    DB_NAME: 'SolveninPOS',
    DB_VERSION: 1,

    async init() {
      if (this.db) return;
      return new Promise((resolve, reject) => {
        const request = indexedDB.open(this.DB_NAME, this.DB_VERSION);
        request.onupgradeneeded = (e) => {
          const db = e.target.result;
          if (!db.objectStoreNames.contains('products')) {
            const store = db.createObjectStore('products', { keyPath: 'id' });
            store.createIndex('barcode', 'barcode', { unique: false });
            store.createIndex('name', 'name', { unique: false });
          }
          if (!db.objectStoreNames.contains('sales_queue')) {
            const store = db.createObjectStore('sales_queue', { keyPath: 'local_id', autoIncrement: true });
            store.createIndex('status', 'status');
            store.createIndex('created_at', 'created_at');
          }
          if (!db.objectStoreNames.contains('quick_buttons')) {
            db.createObjectStore('quick_buttons', { keyPath: 'id' });
          }
          if (!db.objectStoreNames.contains('meta')) {
            db.createObjectStore('meta', { keyPath: 'key' });
          }
        };
        request.onsuccess = (e) => { this.db = e.target.result; resolve(); };
        request.onerror = () => reject(request.error);
      });
    },

    async cacheProducts(products) {
      if (!this.db) await this.init();
      const tx = this.db.transaction('products', 'readwrite');
      const store = tx.objectStore('products');
      await new Promise((r) => { const req = store.clear(); req.onsuccess = r; });
      for (const p of products) {
        store.put({ ...p, cached_at: new Date().toISOString() });
      }
      await new Promise((r, j) => { tx.oncomplete = r; tx.onerror = () => j(tx.error); });
      await this.setMeta('products_cached_at', new Date().toISOString());
      await this.setMeta('products_cached_count', String(products.length));
    },

    async cacheQuickButtons(buttons) {
      if (!this.db) await this.init();
      const tx = this.db.transaction('quick_buttons', 'readwrite');
      const store = tx.objectStore('quick_buttons');
      await new Promise((r) => { const req = store.clear(); req.onsuccess = r; });
      for (const b of buttons) store.put(b);
      await new Promise((r, j) => { tx.oncomplete = r; tx.onerror = () => j(tx.error); });
    },

    async getCachedProducts() {
      if (!this.db) await this.init();
      const tx = this.db.transaction('products', 'readonly');
      const store = tx.objectStore('products');
      return new Promise((resolve, reject) => {
        const req = store.getAll();
        req.onsuccess = () => resolve(req.result || []);
        req.onerror = () => reject(req.error);
      });
    },

    async getCachedQuickButtons() {
      if (!this.db) await this.init();
      const tx = this.db.transaction('quick_buttons', 'readonly');
      const store = tx.objectStore('quick_buttons');
      return new Promise((resolve, reject) => {
        const req = store.getAll();
        req.onsuccess = () => resolve(req.result || []);
        req.onerror = () => reject(req.error);
      });
    },

    async getProductByBarcode(barcode) {
      if (!this.db) await this.init();
      const tx = this.db.transaction('products', 'readonly');
      const store = tx.objectStore('products');
      const index = store.index('barcode');
      return new Promise((resolve, reject) => {
        const req = index.get(barcode);
        req.onsuccess = () => resolve(req.result || null);
        req.onerror = () => reject(req.error);
      });
    },

    async searchProducts(query) {
      const all = await this.getCachedProducts();
      const q = (query || '').toLowerCase();
      return all.filter((p) =>
        (p.name && p.name.toLowerCase().includes(q)) ||
        (p.barcode && p.barcode === query) ||
        (p.sku && p.sku.toLowerCase().includes(q))
      );
    },

    async queueSale(saleData) {
      if (!this.db) await this.init();
      const tx = this.db.transaction('sales_queue', 'readwrite');
      const store = tx.objectStore('sales_queue');
      return new Promise((resolve, reject) => {
        const req = store.add({
          order_data: saleData,
          status: 'pending',
          created_at: new Date().toISOString(),
          retry_count: 0,
        });
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
    },

    async getPendingSales() {
      if (!this.db) await this.init();
      const tx = this.db.transaction('sales_queue', 'readonly');
      const store = tx.objectStore('sales_queue');
      const index = store.index('status');
      return new Promise((resolve, reject) => {
        const req = index.getAll('pending');
        req.onsuccess = () => resolve(req.result || []);
        req.onerror = () => reject(req.error);
      });
    },

    async markSaleSynced(localId) {
      if (!this.db) await this.init();
      const tx = this.db.transaction('sales_queue', 'readwrite');
      const store = tx.objectStore('sales_queue');
      return new Promise((resolve, reject) => {
        const getReq = store.get(localId);
        getReq.onsuccess = () => {
          const sale = getReq.result;
          if (sale) {
            sale.status = 'synced';
            sale.synced_at = new Date().toISOString();
            const putReq = store.put(sale);
            putReq.onsuccess = () => resolve();
            putReq.onerror = () => reject(putReq.error);
          } else resolve();
        };
        getReq.onerror = () => reject(getReq.error);
      });
    },

    async markSaleFailed(localId, errorMsg) {
      if (!this.db) await this.init();
      const tx = this.db.transaction('sales_queue', 'readwrite');
      const store = tx.objectStore('sales_queue');
      return new Promise((resolve, reject) => {
        const getReq = store.get(localId);
        getReq.onsuccess = () => {
          const sale = getReq.result;
          if (sale) {
            sale.retry_count = (sale.retry_count || 0) + 1;
            sale.last_error = errorMsg;
            // Give up after 5 retries to stop hammering the server
            if (sale.retry_count >= 5) sale.status = 'failed';
            const putReq = store.put(sale);
            putReq.onsuccess = () => resolve();
            putReq.onerror = () => reject(putReq.error);
          } else resolve();
        };
        getReq.onerror = () => reject(getReq.error);
      });
    },

    async setMeta(key, value) {
      if (!this.db) await this.init();
      const tx = this.db.transaction('meta', 'readwrite');
      const store = tx.objectStore('meta');
      store.put({ key, value });
      return new Promise((r) => { tx.oncomplete = r; });
    },

    async getMeta(key) {
      if (!this.db) await this.init();
      const tx = this.db.transaction('meta', 'readonly');
      const store = tx.objectStore('meta');
      return new Promise((resolve) => {
        const req = store.get(key);
        req.onsuccess = () => resolve(req.result ? req.result.value : null);
        req.onerror = () => resolve(null);
      });
    },
  };

  const PosConnectivity = {
    isOnline: navigator.onLine,

    init() {
      window.addEventListener('online', async () => {
        this.isOnline = true;
        this._updateBanner(false, 0);
        this._setExitEnabled(true);
        if (window.PosSync) {
          const before = (await PosOfflineDB.getPendingSales()).length;
          await window.PosSync.syncPendingSales();
          const after = (await PosOfflineDB.getPendingSales()).length;
          const synced = before - after;
          if (synced > 0 && typeof showToast === 'function') showToast(`${synced} satış senkronize edildi`, 'success');
        }
      });
      window.addEventListener('offline', () => {
        this.isOnline = false;
        this._updateBanner(true, 0);
        this._setExitEnabled(false);
      });
      // Initial paint
      this._updateBanner(!this.isOnline, 0);
      if (!this.isOnline) this._setExitEnabled(false);
      // Periodic pending count refresh
      setInterval(async () => {
        try {
          const pending = await PosOfflineDB.getPendingSales();
          this._updateBanner(!this.isOnline, pending.length);
        } catch (e) {}
      }, 5000);
    },

    _updateBanner(isOffline, pendingCount) {
      const banner = document.getElementById('pos-offline-banner');
      if (!banner) return;
      const tt = (k, fb) => (typeof t === 'function' ? t(k) : '') || fb;
      if (isOffline || pendingCount > 0) {
        banner.style.display = 'flex';
        banner.style.flexDirection = 'column';
        const main = isOffline
          ? '⚠️ ' + tt('pos_offline_mode', 'Offline mode')
          : '🔄 ' + tt('pos_syncing', 'Syncing pending sales');
        const sub = pendingCount > 0
          ? tt('pos_pending_sales', '{n} sales pending sync').replace('{n}', pendingCount)
          : tt('pos_offline_sync_info', 'Sales are saved locally and will sync when connected');
        banner.innerHTML = `<span>${main}</span><span style="font-size:11px">${sub}</span>`;
        banner.style.background = isOffline ? '#f59e0b' : '#3b82f6';
      } else {
        banner.style.display = 'none';
      }
    },

    _setExitEnabled(enabled) {
      const btn = document.querySelector('.pos-exit');
      if (!btn) return;
      btn.disabled = !enabled;
      btn.style.opacity = enabled ? '' : '0.5';
      btn.style.cursor = enabled ? '' : 'not-allowed';
      btn.title = enabled ? '' : 'Çevrimdışı modda çıkış yapamazsınız. İnternet bağlantısı sağlandıktan sonra çıkış yapın.';
    },
  };

  const PosSync = {
    isSyncing: false,

    async syncPendingSales() {
      if (this.isSyncing) return;
      if (!PosConnectivity.isOnline) return;
      this.isSyncing = true;
      try {
        const pending = await PosOfflineDB.getPendingSales();
        if (!pending.length) return;
        console.log('[POS Sync]', pending.length, 'sales to sync');

        const sb = window._supabase || (window.supabase && window.supabase.createClient
          ? window.supabase.createClient(
              'https://jaakjdzpdizjbzvbtcld.supabase.co',
              'sb_publishable_Zp3NcrPr7yPrL8zgpiNmfA_YF7RGHe9'
            )
          : null);
        if (!sb) return;

        for (const sale of pending) {
          try {
            const items = sale.order_data._items || [];
            const orderPayload = { ...sale.order_data };
            delete orderPayload._items;

            const { data: order, error } = await sb
              .from('sales_orders')
              .insert(orderPayload)
              .select('id')
              .single();
            if (error) throw error;

            if (items.length && order) {
              await sb.from('sales_order_items').insert(
                items.map((it) => ({ ...it, order_id: order.id }))
              );
            }
            await PosOfflineDB.markSaleSynced(sale.local_id);
            console.log('[POS Sync] synced local', sale.local_id, '→', order.id);
          } catch (err) {
            console.error('[POS Sync] failed', sale.local_id, err);
            await PosOfflineDB.markSaleFailed(sale.local_id, err.message || String(err));
          }
        }
      } finally {
        this.isSyncing = false;
        PosConnectivity._updateBanner(!PosConnectivity.isOnline,
          (await PosOfflineDB.getPendingSales()).length);
      }
    },
  };

  /**
   * Try to insert a sale online; if offline (or insert fails) queue it
   * locally for later sync. Returns { success, mode: 'online'|'offline', id }.
   *
   * saleData should be the sales_orders row WITH a special _items array
   * that holds the matching sales_order_items rows. We strip _items before
   * insert and submit them as a second insert once the order has an id.
   */
  async function completeSaleOfflineFirst(saleData) {
    const items = saleData._items || [];
    const orderPayload = { ...saleData };
    delete orderPayload._items;

    if (PosConnectivity.isOnline) {
      try {
        const sb = window._supabase;
        const { data: order, error } = await sb
          .from('sales_orders')
          .insert(orderPayload)
          .select('id')
          .single();
        if (error) throw error;
        if (items.length) {
          await sb.from('sales_order_items').insert(
            items.map((it) => ({ ...it, order_id: order.id }))
          );
        }
        return { success: true, mode: 'online', id: order.id };
      } catch (err) {
        // Online insert failed → fall back to queue
        const localId = await PosOfflineDB.queueSale(saleData);
        return { success: true, mode: 'offline', id: 'local_' + localId, error: err.message };
      }
    } else {
      const localId = await PosOfflineDB.queueSale(saleData);
      return { success: true, mode: 'offline', id: 'local_' + localId };
    }
  }

  // Expose
  window.PosOfflineDB = PosOfflineDB;
  window.PosConnectivity = PosConnectivity;
  window.PosSync = PosSync;
  window.completeSaleOfflineFirst = completeSaleOfflineFirst;
})();
