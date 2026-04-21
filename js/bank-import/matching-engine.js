/**
 * Bank Import — Matching Engine
 *
 * 6-layer transaction → entity matcher. Pure function; caller is responsible
 * for persistence. Same code runs in the browser (window.BankImportMatcher)
 * and in Node for smoke testing.
 *
 * Layers (first hit wins):
 *   0. duplicate        — same external_reference already in bank_transactions
 *   1. own_transfer     — counterparty BIN == company tax_number
 *   2. BIN exact        — contact.tax_number or employee.tax_number
 *   3. special pattern  — commission / tax / salary keywords → expense account
 *   4. fuzzy name       — ≥0.95 auto contact, ≥0.80 suggestion
 *   5. unmatched        — manual resolution required
 */
(function (root, factory) {
  const fuzzy = typeof require !== 'undefined'
    ? require('./fuzzy-match')
    : (root.BankImportFuzzy);
  const api = factory(fuzzy);
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.BankImportMatcher = api;
})(typeof self !== 'undefined' ? self : this, function (fuzzy) {
  'use strict';

  // Confidence thresholds — shared constants so UI banners can reference.
  const THRESHOLDS = Object.freeze({
    AUTO: 0.95,        // ≥ → match_type=contact (no user action required)
    SUGGEST: 0.80,     // ≥ → match_type=suggestion (awaits user confirmation)
    EMP_SALARY: 0.75   // for salary-pattern employee resolution
  });

  // Keyword buckets — patterns are case-insensitive. Expand conservatively:
  // a false positive here (tax keyword hits a non-tax vendor) turns a
  // confident contact match into a wrong expense-account match.
  const COMMISSION_PATTERNS = [
    /коммис[сc]/i, /komis[sy]on/i, /commission/i, /\bbank\s*fee\b/i, /банк.*сбор/i
  ];
  const TAX_PATTERNS = [
    /\bналог\b/i, /\bvergi\b/i, /\btax\b/i, /\bУГД\b/, /РГУ.*доход/i,
    /зем[еe]льный/i, /\bимуществ/i, /подоход/i
  ];
  const SALARY_PATTERNS = [
    /зарплат/i, /\bmaas\b/i, /\bmaaş\b/i, /\bsalary\b/i, /payroll/i,
    /оплат.*труд/i, /заработн/i
  ];

  // Expense-account name hints, in priority order.
  const ACCOUNT_HINTS = {
    commission: ['komis', 'commis', 'комис', 'bank fee', 'banka'],
    tax:        ['vergi', 'налог', 'tax', 'земельн', 'имуществ', 'подоход']
  };

  // ─── HELPERS ──────────────────────────────────────────────

  function testAny(patterns, ...texts) {
    return patterns.some(p => texts.some(t => t && p.test(t)));
  }

  /**
   * BCC-style layouts put both the account owner's BIN and the counterparty's
   * BIN in the same row text. Step 2's generic /\b\d{12}\b/ regex picks
   * whichever comes first, often our own BIN. If counterparty_bin equals
   * ownBin *and* payment_details / counterparty_name contain a different
   * 12-digit BIN, prefer that one. Otherwise the match is genuinely own.
   */
  function resolveCounterpartyBin(line, ownBin) {
    const raw = line.counterparty_bin;
    if (!raw || !ownBin || raw !== ownBin) return raw;
    const text = [line.payment_details, line.counterparty_name].filter(Boolean).join(' ');
    const all = text.match(/\b\d{12}\b/g) || [];
    return all.find(b => b !== ownBin) || raw;
  }

  function findAccountByHints(accounts, hints) {
    if (!accounts?.length) return null;
    const lowerHints = hints.map(h => h.toLowerCase());
    for (const h of lowerHints) {
      const hit = accounts.find(a => (a.name || '').toLowerCase().includes(h));
      if (hit) return hit;
    }
    return null;
  }

  function findEmployeeByName(employees, name) {
    if (!employees?.length || !name) return null;
    const candidates = employees.map(e => ({
      id: e.id,
      name: [e.first_name, e.last_name].filter(Boolean).join(' '),
      tax_number: e.tax_number
    }));
    const best = fuzzy.findBestMatch({ name }, candidates);
    if (!best) return null;
    const full = employees.find(x => x.id === best.contact.id);
    return { employee: full, score: best.score };
  }

  // ─── MAIN ─────────────────────────────────────────────────

  /**
   * Classify one data_import_lines row.
   * @param {object} line     — {counterparty_name, counterparty_bin, counterparty_iban,
   *                             external_reference, payment_details, debit, credit, ...}
   * @param {object} context  — contacts[], employees[], bankAccounts[], expenseAccounts[],
   *                             settings{}, ownBin, currentAccountId, existingBankTransactions[]
   * @returns {object}        — { match_type, confidence?, matched_*_id?, suggested_contact_id?,
   *                             suggestion_reason?, target_bank_account_id?, auto_bin_update?,
   *                             duplicate_of_bank_tx_id? }
   */
  function matchTransaction(line, context) {
    const ctx = context || {};
    const ref = line.external_reference;
    const resolvedBin = resolveCounterpartyBin(line, ctx.ownBin);

    // ── Layer 0: duplicate ──
    if (ref && ctx.existingBankTransactions?.length) {
      const existing = ctx.existingBankTransactions.find(tx => tx.external_reference === ref);
      if (existing) {
        return {
          match_type: 'duplicate',
          duplicate_of_bank_tx_id: existing.id,
          confidence: 1
        };
      }
    }

    // ── Layer 1: own transfer ──
    // Only trigger when the resolved BIN (not just the raw field) matches own.
    if (resolvedBin && ctx.ownBin && resolvedBin === ctx.ownBin) {
      const otherAccount = (ctx.bankAccounts || []).find(a =>
        a.id !== ctx.currentAccountId &&
        (a.iban && line.counterparty_iban && a.iban === line.counterparty_iban)
      );
      return {
        match_type: 'own_transfer',
        target_bank_account_id: otherAccount?.id || null,
        confidence: otherAccount ? 1 : 0.7
      };
    }

    // ── Layer 2: BIN exact ──
    if (resolvedBin) {
      const byBin = (ctx.contacts || []).find(c => c.tax_number === resolvedBin);
      if (byBin) {
        return {
          match_type: 'contact',
          matched_contact_id: byBin.id,
          confidence: 1
        };
      }
      if (ctx.settings?.bank_import_salary_mode === 'employee') {
        const byBinEmp = (ctx.employees || []).find(e => e.tax_number === resolvedBin);
        if (byBinEmp) {
          return {
            match_type: 'employee',
            matched_employee_id: byBinEmp.id,
            confidence: 1
          };
        }
      }
    }

    // ── Layer 3: special patterns ──
    const details = line.payment_details || '';
    const name = line.counterparty_name || '';

    if (testAny(COMMISSION_PATTERNS, details, name) &&
        ctx.settings?.bank_import_commission_mode === 'expense_account') {
      const acc = findAccountByHints(ctx.expenseAccounts, ACCOUNT_HINTS.commission);
      if (acc) {
        return {
          match_type: 'expense_account',
          matched_account_id: acc.id,
          suggestion_reason: 'commission_keyword',
          confidence: 0.85
        };
      }
    }

    if (testAny(TAX_PATTERNS, details, name) &&
        ctx.settings?.bank_import_tax_mode === 'expense_account') {
      const acc = findAccountByHints(ctx.expenseAccounts, ACCOUNT_HINTS.tax);
      if (acc) {
        return {
          match_type: 'expense_account',
          matched_account_id: acc.id,
          suggestion_reason: 'tax_keyword',
          confidence: 0.85
        };
      }
    }

    if (testAny(SALARY_PATTERNS, details) && name) {
      const emp = findEmployeeByName(ctx.employees, name);
      if (emp && emp.score >= THRESHOLDS.EMP_SALARY) {
        return {
          match_type: 'employee',
          matched_employee_id: emp.employee.id,
          suggestion_reason: 'salary_pattern',
          confidence: emp.score
        };
      }
    }

    // ── Layer 4: fuzzy name ──
    if (name && ctx.contacts?.length) {
      const best = fuzzy.findBestMatch(
        { name, bin: resolvedBin },
        ctx.contacts
      );
      if (best) {
        // If the candidate has no BIN but the line does, propose auto-fill.
        const autoBin = (resolvedBin && !best.contact.tax_number)
          ? resolvedBin
          : null;

        if (best.score >= THRESHOLDS.AUTO) {
          return {
            match_type: 'contact',
            matched_contact_id: best.contact.id,
            confidence: best.score,
            auto_bin_update: autoBin
          };
        }
        if (best.score >= THRESHOLDS.SUGGEST) {
          return {
            match_type: 'suggestion',
            suggested_contact_id: best.contact.id,
            confidence: best.score,
            auto_bin_update: autoBin
          };
        }
      }
    }

    // ── Layer 5: unmatched ──
    return {
      match_type: 'unmatched',
      confidence: 0,
      suggestion_reason: name ? 'create_contact' : 'manual_select'
    };
  }

  /**
   * Build a ready-to-pass context from raw DB fetches. Normalizes fields the
   * engine cares about so callers don't have to.
   */
  function buildContext(raw) {
    const {
      contacts = [],
      employees = [],
      bankAccounts = [],
      expenseAccounts = [],
      settings = {},
      ownBin = null,
      currentAccountId = null,
      existingBankTransactions = []
    } = raw || {};

    const s = {
      bank_import_commission_mode: settings.bank_import_commission_mode || 'expense_account',
      bank_import_tax_mode:        settings.bank_import_tax_mode        || 'expense_account',
      bank_import_salary_mode:     settings.bank_import_salary_mode     || 'employee'
    };

    return {
      contacts, employees, bankAccounts, expenseAccounts,
      settings: s, ownBin, currentAccountId, existingBankTransactions
    };
  }

  /**
   * Classify a batch of lines in-memory. Returns the per-line results in the
   * same order as input.
   */
  function matchBatch(lines, context) {
    return (lines || []).map(line => ({ line, result: matchTransaction(line, context) }));
  }

  return {
    matchTransaction,
    matchBatch,
    buildContext,
    THRESHOLDS
  };
});
