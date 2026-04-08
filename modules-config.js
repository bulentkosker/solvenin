/* modules-config.js — Solvenin module catalog
   Used by:
     - sidebar.js for visibility filtering
     - settings.html "Modules" tab toggles
     - dashboard.html new-company onboarding picker
     - create_company_for_user RPC seed list (mirrored server-side)

   IMPORTANT: column names match the existing company_modules table:
     module      varchar  -- the key (NOT module_key)
     is_active   boolean  -- enabled flag (NOT is_enabled)
*/
(function () {
  const STANDARD = [
    { key: 'inventory',   icon: '📦', i18n: 'module_inventory'   },
    { key: 'sales',       icon: '💰', i18n: 'module_sales'       },
    { key: 'purchasing',  icon: '🛒', i18n: 'module_purchasing'  },
    { key: 'contacts',    icon: '👥', i18n: 'module_contacts'    },
    { key: 'finance',     icon: '🏦', i18n: 'module_finance'     },
    { key: 'accounting',  icon: '📊', i18n: 'module_accounting'  },
    { key: 'hr',          icon: '👤', i18n: 'module_hr'          },
    { key: 'production',  icon: '🏭', i18n: 'module_production'  },
    { key: 'projects',    icon: '📋', i18n: 'module_projects'    },
    { key: 'shipping',    icon: '🚚', i18n: 'module_shipping'    },
    { key: 'maintenance', icon: '🔧', i18n: 'module_maintenance' },
    { key: 'crm',         icon: '🎯', i18n: 'module_crm'         },
    { key: 'reports',     icon: '📈', i18n: 'module_reports'     },
  ];

  const SECTOR = [
    { key: 'pos',        icon: '🖥️', i18n: 'module_pos',        descKey: 'module_pos_desc' },
    { key: 'restaurant', icon: '🍽️', i18n: 'module_restaurant', descKey: 'module_restaurant_desc' },
    { key: 'hotel',      icon: '🏨', i18n: 'module_hotel',      descKey: 'module_hotel_desc' },
    { key: 'clinic',     icon: '🏥', i18n: 'module_clinic',     descKey: 'module_clinic_desc' },
    { key: 'elevator',   icon: '🌾', i18n: 'module_elevator',   descKey: 'module_elevator_desc' },
    { key: 'ecommerce',  icon: '🛍️', i18n: 'module_ecommerce',  descKey: 'module_ecommerce_desc' },
  ];

  // Mapping: which sidebar nav keys (used in sidebar.js NAV) belong to each module.
  // sidebar.js applyModuleVisibility() will hide nav items whose key is in here
  // when the corresponding module's is_active is false.
  const MODULE_NAV_MAP = {
    inventory:   ['nav_inventory'],
    sales:       ['nav_sales'],
    purchasing:  ['nav_purchasing'],
    contacts:    ['nav_contacts', 'nav_cariler'],
    finance:     ['nav_cashbank', 'nav_finance'],
    accounting:  ['nav_accounting'],
    hr:          ['nav_hr'],
    production:  ['nav_production'],
    projects:    ['nav_projects'],
    shipping:    ['nav_shipping'],
    maintenance: ['nav_maintenance'],
    crm:         ['nav_crm'],
    reports:     ['nav_reports'],
    pos:         ['nav_pos'],
    restaurant:  ['nav_restaurant'],
    hotel:       ['nav_hotel'],
    clinic:      ['nav_clinic'],
    elevator:    ['nav_elevator'],
    ecommerce:   ['nav_ecommerce'],
  };

  // Default state for a brand-new company (mirrored in the SQL RPC seed)
  const DEFAULT_ENABLED = new Set(STANDARD.map((m) => m.key));
  // sector modules are off by default

  function isStandard(key)   { return STANDARD.some((m) => m.key === key); }
  function isSector(key)     { return SECTOR.some((m) => m.key === key); }
  function find(key)         { return [...STANDARD, ...SECTOR].find((m) => m.key === key) || null; }
  function defaultActive(key){ return DEFAULT_ENABLED.has(key); }

  window.ModulesConfig = {
    STANDARD,
    SECTOR,
    MODULE_NAV_MAP,
    DEFAULT_ENABLED,
    isStandard,
    isSector,
    find,
    defaultActive,
    all() { return [...STANDARD, ...SECTOR]; },
  };
})();
