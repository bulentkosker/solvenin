# Solvenin Migration Rules

## Golden Rule: Every Migration Must Be Backward Compatible

The currently-deployed application code must keep working immediately
after a migration runs, without any code changes. This is the only way
we can ship migrations safely without coordinated downtime.

### ✅ Allowed (zero-downtime)
- Add a new **column** with a `DEFAULT` value
- Add a new **table**
- Add a new **index** (preferably `CREATE INDEX CONCURRENTLY` on big tables)
- Add a new **RPC / function**
- Make a column **nullable**
- `CREATE OR REPLACE FUNCTION` when the return type is unchanged
- Add a new **RLS policy** (or relax an existing one)

### ❌ Forbidden (will break the live app)
- **Drop a column** (the old code may still SELECT or INSERT it)
- **Rename a column**
- **Change a column type** (use add-new + backfill + drop-old over multiple deploys)
- **Add a `NOT NULL` constraint** to a column that already has data
- **Drop a table**
- **Tighten an RLS policy** in a way that hides currently-visible rows

### Drop / Rename Procedure (4-step ladder)
1. **Migration A** — add the new column / new name (backward-compatible)
2. **Code change** — switch the app to use the new column/name
3. **Deploy** + soak for 1-2 days, watching errors
4. **Migration B** — drop the old column/name

### Critical Migrations (NOT backward-compatible)
If you absolutely must run a non-backward-compatible migration:
1. **Turn ON maintenance mode** via the feature flag (`maintenance_mode = true`)
2. Wait ~10 seconds — every page in flight will redirect users to `/maintenance.html`
3. Run the migration
4. Deploy the new code
5. Smoke test
6. **Turn OFF maintenance mode**
- Target window: **15 minutes maximum**

### Migration File Format
Numbered, lowercase, snake_case, immutable once committed. Example:

```sql
-- Migration: 007_my_new_feature
-- Description: Adds a new my_field column to products
-- Backward Compatible: YES
-- Rollback:
--   ALTER TABLE products DROP COLUMN IF EXISTS my_field;

-- UP
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS my_field text;

-- Log
INSERT INTO migrations_log (file_name, notes)
VALUES ('007_my_new_feature.sql', 'Adds my_field column to products')
ON CONFLICT (file_name) DO NOTHING;
```

### Where Migrations Live

| Folder | Purpose |
|--------|---------|
| `/migrations` | **Numbered, immutable, audited.** This is the canonical history. Never edit a file here after it has been committed and pushed to main. |
| `/seeds` | Older one-shot migration scripts that pre-date the numbered system. Treated as historical archives. |

### How to Run a Migration

The project does not use the Supabase CLI. Migrations are executed via
the `exec_sql` RPC function with the service-role key:

```js
// node + .env (SUPABASE_URL, SUPABASE_SERVICE_KEY)
const sql = fs.readFileSync('migrations/007_my_new_feature.sql', 'utf8');
await fetch(URL+'/rest/v1/rpc/exec_sql', {
  method:'POST',
  headers:{apikey:KEY, Authorization:'Bearer '+KEY, 'Content-Type':'application/json'},
  body: JSON.stringify({query: sql})
});
```

After running, **PostgREST schema cache** sometimes needs a kick:
```sql
NOTIFY pgrst, 'reload schema';
```

### Audit

Every successful migration is recorded in the `migrations_log` table.
Query with:

```sql
SELECT file_name, executed_at, status
FROM migrations_log ORDER BY id;
```

### Service Panel Integration

The `🔧 Veri Onarım` section in `service-panel.html` reads `migrations_log`
to show the last 20 migrations and their timestamps. This is a read-only
audit view for the operator.
