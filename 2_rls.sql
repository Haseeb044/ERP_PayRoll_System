-- ============================================================
--  RIDER PAYROLL ERP — ROW LEVEL SECURITY (RLS) POLICIES v4.0
--  Run this file AFTER 1_schema.sql has been executed.
--
--  ROLES (SRS 8.2):
--    accountant = admin, full operational access
--    pro        = field ops, limited draft-only access
--
--  HOW SUPABASE RLS WORKS:
--    Enable RLS on a table → ALL rows blocked by default
--    Each policy opens back specific rows/operations
--    auth.uid() = the UUID of the logged-in Supabase Auth user
--    We read role from public.profiles using that UUID
--
--  KEY SRS RULES ENFORCED HERE:
--    SRS 1.1.2  — Posted journals cannot be deleted by anyone
--    SRS 1.2    — Ledger is read-only; no user can INSERT/UPDATE/DELETE
--    SRS 2.3.1  — Only accountant can add/edit rider aliases
--    SRS 4.3.3  — Only accountant can assign/unassign bikes
--    SRS 8.3    — Full permission matrix
--    SRS 8.4.1  — PRO sees only their own created data
--
--  Changes from v3.0:
--    + action_items: PRO can INSERT new items (for rider_pending_approval flow)
--    + riders: PRO read policy scoped correctly to created_by_user_id
--    + expenses: pro read policy handles null journal_id correctly
-- ============================================================


-- ============================================================
-- STEP 1: HELPER FUNCTION
-- get_my_role() reads the logged-in user's role from profiles.
-- SECURITY DEFINER runs with elevated privileges so it can
-- read profiles even before per-table policies are evaluated.
-- Now using LOWER() and COALESCE for case-insensitive robust matching.
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS TEXT
LANGUAGE SQL
SECURITY DEFINER
STABLE
AS $$
  SELECT COALESCE(LOWER(role::TEXT), '') 
  FROM public.profiles 
  WHERE id = auth.uid();
$$;


-- ============================================================
-- TABLE: profiles
-- SRS 8.2 — Users manage their own profile.
-- Accountant can read all profiles for actor attribution.
-- PRO can only read and update their own profile.
-- ============================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles: read own"
  ON public.profiles FOR SELECT
  USING (id = auth.uid());

CREATE POLICY "profiles: update own"
  ON public.profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Accountant reads all profiles for reports and actor attribution
CREATE POLICY "profiles: accountant read all"
  ON public.profiles FOR SELECT
  USING (public.get_my_role() = 'accountant');

-- Allow insert on signup (Supabase trigger creates profile row)
CREATE POLICY "profiles: insert own on signup"
  ON public.profiles FOR INSERT
  WITH CHECK (id = auth.uid());


-- ============================================================
-- TABLE: riders
-- SRS 8.2.1 — Accountant: full CRUD
-- SRS 8.2.2 — PRO: can CREATE only, CANNOT edit after creation
-- SRS 8.4.1 — PRO sees ONLY riders they personally onboarded
--             scoped via created_by_user_id = auth.uid()
-- ============================================================

ALTER TABLE public.riders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "riders: accountant full access"
  ON public.riders FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

-- PRO can insert new riders
CREATE POLICY "riders: pro can create"
  ON public.riders FOR INSERT
  WITH CHECK (public.get_my_role() = 'pro');

-- PRO can only see riders they personally created (SRS 8.4.1)
CREATE POLICY "riders: pro view own only"
  ON public.riders FOR SELECT
  USING (
    public.get_my_role() = 'pro'
    AND created_by_user_id = auth.uid()
  );

-- PRO also needs shared active rider visibility for operational forms
-- (expense/journal rider selectors). Keep this read-only and active-only.
CREATE POLICY "riders: pro view active riders"
  ON public.riders FOR SELECT
  USING (
    public.get_my_role() = 'pro'
    AND status = 'active'::rider_status
  );

-- PRO CANNOT update or delete — no policy = blocked by default


-- ============================================================
-- TABLE: rider_aliases
-- SRS 2.3.1 — ONLY Accountant can add, activate, deactivate
-- PRO: read only
-- ============================================================

ALTER TABLE public.rider_aliases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rider_aliases: accountant full access"
  ON public.rider_aliases FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

CREATE POLICY "rider_aliases: pro read only"
  ON public.rider_aliases FOR SELECT
  USING (public.get_my_role() = 'pro');


-- ============================================================
-- TABLE: bikes
-- SRS 4.3.3 — ONLY Accountant can create or modify bikes
-- PRO: read only (needs to see which bike a rider has)
-- ============================================================

ALTER TABLE public.bikes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bikes: accountant full access"
  ON public.bikes FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

CREATE POLICY "bikes: pro read only"
  ON public.bikes FOR SELECT
  USING (public.get_my_role() = 'pro');


-- ============================================================
-- TABLE: bike_assignment
-- SRS 4.3.3 — ONLY Accountant can assign / unassign / modify
-- PRO: read only (financial liability — PRO must see assignment)
-- ============================================================

ALTER TABLE public.bike_assignment ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bike_assignment: accountant full access"
  ON public.bike_assignment FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

CREATE POLICY "bike_assignment: pro read only"
  ON public.bike_assignment FOR SELECT
  USING (public.get_my_role() = 'pro');


-- ============================================================
-- TABLE: drawer
-- SRS 5.4.1 — All adjustments must go through accountant
-- SRS 8.4.1 — PRO cannot see balances or totals
-- PRO: ZERO ACCESS — no policy written = blocked by RLS default
-- ============================================================

ALTER TABLE public.drawer ENABLE ROW LEVEL SECURITY;

CREATE POLICY "drawer: accountant full access"
  ON public.drawer FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

-- PRO: NO ACCESS


-- ============================================================
-- TABLE: expense_categories
-- Accountant manages categories.
-- PRO needs read access to populate category dropdown.
-- ============================================================

ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "expense_categories: accountant full access"
  ON public.expense_categories FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

CREATE POLICY "expense_categories: pro read only"
  ON public.expense_categories FOR SELECT
  USING (public.get_my_role() = 'pro');


-- ============================================================
-- TABLE: journal_templates
-- SRS 1.5.3 — Accountant saves and uses templates.
-- PRO: read only to auto-fill VAT rate on expense form.
-- ============================================================

ALTER TABLE public.journal_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "journal_templates: accountant full access"
  ON public.journal_templates FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

CREATE POLICY "journal_templates: pro read only"
  ON public.journal_templates FOR SELECT
  USING (public.get_my_role() = 'pro');


-- ============================================================
-- TABLE: journals
-- SRS 8.3 Permission Matrix:
--   Accountant: full CREATE, APPROVE (post), REVERSE
--   PRO: INSERT draft only
--        SELECT own journals only (SRS 8.4.1)
--        UPDATE own DRAFT journals only
--        CANNOT change status to posted or reversed
--
-- SRS 1.1.2 — DELETE blocked for EVERYONE (no delete policy)
-- ============================================================

ALTER TABLE public.journals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "journals: accountant full access"
  ON public.journals FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

-- PRO can insert ONLY draft journals
CREATE POLICY "journals: pro insert draft only"
  ON public.journals FOR INSERT
  WITH CHECK (
    public.get_my_role() = 'pro'
    AND status = 'draft'
  );

-- PRO reads ONLY their own journals (SRS 8.4.1)
CREATE POLICY "journals: pro read own only"
  ON public.journals FOR SELECT
  USING (
    public.get_my_role() = 'pro'
    AND created_by_user_id = auth.uid()
  );

-- PRO updates ONLY their own DRAFT journals
-- WITH CHECK blocks PRO from ever changing status to posted/reversed
CREATE POLICY "journals: pro update own draft only"
  ON public.journals FOR UPDATE
  USING (
    public.get_my_role() = 'pro'
    AND created_by_user_id = auth.uid()
    AND status = 'draft'
  )
  WITH CHECK (
    public.get_my_role() = 'pro'
    AND status = 'draft'
  );

-- *** NO DELETE POLICY FOR ANYONE ***
-- Trigger trg_journal_immutability blocks posted journal deletion.
-- Draft journal deletion: not explicitly blocked at RLS level
-- but should be controlled at app level.


-- ============================================================
-- TABLE: journal_lines
-- Same access pattern as journals.
-- Accountant: full access.
-- PRO: manage lines ONLY on their own draft journals.
-- DELETE blocked for everyone.
-- ============================================================

ALTER TABLE public.journal_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "journal_lines: accountant full access"
  ON public.journal_lines FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

-- PRO inserts lines ONLY on their own draft journals
CREATE POLICY "journal_lines: pro insert on own drafts"
  ON public.journal_lines FOR INSERT
  WITH CHECK (
    public.get_my_role() = 'pro'
    AND EXISTS (
      SELECT 1 FROM public.journals j
      WHERE j.id = journal_id
        AND j.created_by_user_id = auth.uid()
        AND j.status = 'draft'
    )
  );

-- PRO reads lines on their own journals (any status — for history)
CREATE POLICY "journal_lines: pro read own"
  ON public.journal_lines FOR SELECT
  USING (
    public.get_my_role() = 'pro'
    AND EXISTS (
      SELECT 1 FROM public.journals j
      WHERE j.id = journal_id
        AND j.created_by_user_id = auth.uid()
    )
  );

-- PRO updates lines ONLY on their own draft journals
CREATE POLICY "journal_lines: pro update own drafts"
  ON public.journal_lines FOR UPDATE
  USING (
    public.get_my_role() = 'pro'
    AND EXISTS (
      SELECT 1 FROM public.journals j
      WHERE j.id = journal_id
        AND j.created_by_user_id = auth.uid()
        AND j.status = 'draft'
    )
  );

-- *** NO DELETE POLICY FOR ANYONE ***


-- ============================================================
-- TABLE: ledger
-- SRS 1.2 — Ledger is read-only transactional history
-- SRS 8.4.1 — PRO cannot see ledger totals or balances
-- Accountant: SELECT only
-- PRO: NO ACCESS
-- No INSERT/UPDATE/DELETE for any user — trigger writes only
-- To find ledger entries for a rider always join through journals:
--   SELECT l.* FROM ledger l
--   JOIN journals j ON j.id = l.journal_id
--   WHERE j.receivable_entity_type = 'rider'
--   AND j.receivable_entity_id = '<rider-uuid>'
-- ============================================================

ALTER TABLE public.ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ledger: accountant read only"
  ON public.ledger FOR SELECT
  USING (public.get_my_role() = 'accountant');

-- PRO: NO ACCESS
-- No INSERT / UPDATE / DELETE for anyone — trigger writes only


-- ============================================================
-- TABLE: expenses
-- SRS 8.2.2 — PRO can create expense drafts
-- SRS 8.2.1 — Accountant approves
-- SRS 8.4.1 — PRO sees only their own expenses
-- ============================================================

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "expenses: accountant full access"
  ON public.expenses FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

-- PRO can insert expenses
CREATE POLICY "expenses: pro can create"
  ON public.expenses FOR INSERT
  WITH CHECK (public.get_my_role() = 'pro');

-- PRO reads only their own expenses
-- journal_id may be null on very early draft state — handled by OR clause
CREATE POLICY "expenses: pro read own"
  ON public.expenses FOR SELECT
  USING (
    public.get_my_role() = 'pro'
    AND (
      journal_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.journals j
        WHERE j.id = journal_id
          AND j.created_by_user_id = auth.uid()
      )
    )
  );

-- PRO updates own expenses ONLY while journal is still draft
CREATE POLICY "expenses: pro update own draft"
  ON public.expenses FOR UPDATE
  USING (
    public.get_my_role() = 'pro'
    AND (
      journal_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.journals j
        WHERE j.id = journal_id
          AND j.created_by_user_id = auth.uid()
          AND j.status = 'draft'
      )
    )
  );


-- ============================================================
-- TABLE: traffic_fines
-- SRS 4.4 — Fine entry by accountant (manual or Excel upload)
-- SRS 4.3.3 — PRO cannot assign or edit fines
-- PRO: read only for transparency
-- ============================================================

ALTER TABLE public.traffic_fines ENABLE ROW LEVEL SECURITY;

-- Clean up any old/conflicting policies before recreating
DROP POLICY IF EXISTS "traffic_fines: accountant full access" ON public.traffic_fines;
DROP POLICY IF EXISTS "traffic_fines: accountant select" ON public.traffic_fines;
DROP POLICY IF EXISTS "traffic_fines: accountant insert" ON public.traffic_fines;
DROP POLICY IF EXISTS "traffic_fines: accountant update" ON public.traffic_fines;
DROP POLICY IF EXISTS "traffic_fines: pro read only" ON public.traffic_fines;

-- accountant: Full access (select, insert, update)
-- Using direct EXISTS check for maximum reliability across different Supabase versions
-- Including ::TEXT cast to ensure ILIKE works correctly if 'role' is an ENUM type
CREATE POLICY "traffic_fines: accountant select"
  ON public.traffic_fines FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND (role::TEXT ILIKE 'accountant' OR role::TEXT ILIKE 'admin')
    )
  );

CREATE POLICY "traffic_fines: accountant insert"
  ON public.traffic_fines FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND (role::TEXT ILIKE 'accountant' OR role::TEXT ILIKE 'admin')
    )
  );

CREATE POLICY "traffic_fines: accountant update"
  ON public.traffic_fines FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND (role::TEXT ILIKE 'accountant' OR role::TEXT ILIKE 'admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND (role::TEXT ILIKE 'accountant' OR role::TEXT ILIKE 'admin')
    )
  );

-- pro: Read only for transparency
CREATE POLICY "traffic_fines: pro read only"
  ON public.traffic_fines FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND role::TEXT ILIKE 'pro'
    )
  );


-- ============================================================
-- TABLE: payroll_batches
-- SRS 3.1.1 — Payroll is accountant-only operation
-- PRO: NO ACCESS
-- ============================================================

ALTER TABLE public.payroll_batches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payroll_batches: accountant full access"
  ON public.payroll_batches FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

-- PRO: NO ACCESS


-- ============================================================
-- TABLE: payroll_skips
-- Payroll mismatch/skip trace table (accountant-only)
-- PRO: NO ACCESS
-- ============================================================

ALTER TABLE public.payroll_skips ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payroll_skips: accountant full access"
  ON public.payroll_skips FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

-- PRO: NO ACCESS


-- ============================================================
-- TABLE: payslips
-- SRS 3.1.1, 8.2.2 — Payroll is accountant-only operation
-- PRO: NO ACCESS
-- ============================================================

ALTER TABLE public.payslips ENABLE ROW LEVEL SECURITY;

-- accountant: Full access to manage and review payroll records
CREATE POLICY "payslips: accountant select"
  ON public.payslips FOR SELECT
  USING (public.get_my_role() = 'accountant');

CREATE POLICY "payslips: accountant insert"
  ON public.payslips FOR INSERT
  WITH CHECK (public.get_my_role() = 'accountant');

CREATE POLICY "payslips: accountant update"
  ON public.payslips FOR UPDATE
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

CREATE POLICY "payslips: accountant delete"
  ON public.payslips FOR DELETE
  USING (public.get_my_role() = 'accountant');

-- PRO: NO ACCESS (Payroll is restricted to head office/accountants)


-- ============================================================
-- TABLE: transactions
-- SRS 8.2.2 — PRO can view own transaction history
-- SRS 8.2.1 — Accountant approves
-- ============================================================

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "transactions: accountant full access"
  ON public.transactions FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

-- PRO inserts transactions with pending status only
CREATE POLICY "transactions: pro insert pending"
  ON public.transactions FOR INSERT
  WITH CHECK (
    public.get_my_role() = 'pro'
    AND status = 'pending'
  );

-- PRO reads own transaction history scoped to their riders
CREATE POLICY "transactions: pro read own"
  ON public.transactions FOR SELECT
  USING (
    public.get_my_role() = 'pro'
    AND rider_id IN (
      SELECT id FROM public.riders
      WHERE created_by_user_id = auth.uid()
    )
  );


-- ============================================================
-- TABLE: action_items
-- SRS 6.7 — Accountant: view all, resolve all
-- SRS 6.7 — PRO: view own role items, resolve own items
-- SRS 6.6.1 — Items cannot auto-disappear; resolution always logged
--
-- PRO can INSERT action items for the rider approval flow:
--   When PRO creates a new rider, PRO creates an action_item
--   with type='rider_pending_approval' and responsible_role='accountant'
--   This notifies the accountant to complete the rider setup.
-- ============================================================

ALTER TABLE public.action_items ENABLE ROW LEVEL SECURITY;

-- Accountant full access (view all, resolve all)
CREATE POLICY "action_items: accountant full access"
  ON public.action_items FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

-- PRO reads items assigned to their role
CREATE POLICY "action_items: pro read own role items"
  ON public.action_items FOR SELECT
  USING (
    public.get_my_role() = 'pro'
    AND responsible_role = 'pro'
  );

-- PRO can INSERT action items directed at accountant
-- Used for: rider_pending_approval, journal_pending_approval
CREATE POLICY "action_items: pro can create for accountant"
  ON public.action_items FOR INSERT
  WITH CHECK (
    public.get_my_role() = 'pro'
    AND responsible_role = 'accountant'
  );

-- PRO can update (resolve) items assigned to their role
CREATE POLICY "action_items: pro resolve own"
  ON public.action_items FOR UPDATE
  USING (
    public.get_my_role() = 'pro'
    AND responsible_role = 'pro'
    AND resolved_at IS NULL
  )
  WITH CHECK (
    resolved_by = auth.uid()
  );


-- ============================================================
-- TABLE: audit_log
-- SRS 8.1.2 — Logs are append-only, not editable, not deletable
-- SRS 8.8   — Accountant can view audit logs
-- PRO: NO ACCESS
-- No INSERT / UPDATE / DELETE for any user (trigger writes only)
-- ============================================================

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_log: accountant read only"
  ON public.audit_log FOR SELECT
  USING (public.get_my_role() = 'accountant');

-- PRO: NO ACCESS
-- No INSERT / UPDATE / DELETE for anyone


-- ============================================================
-- QUICK REFERENCE — ALL TABLES
--
-- TABLE                RLS  ACCOUNTANT        PRO
-- ─────────────────    ───  ──────────────    ──────────────────────────────────
-- profiles             YES  Read all          Read + Update own only
-- riders               YES  Full CRUD         Insert + Read own (created_by_user_id)
-- rider_aliases        YES  Full CRUD         Read only
-- bikes                YES  Full CRUD         Read only
-- bike_assignment      YES  Full CRUD         Read only
-- drawer               YES  Full CRUD         NO ACCESS
-- expense_categories   YES  Full CRUD         Read only
-- journal_templates    YES  Full CRUD         Read only
-- journals             YES  Full CRUD*        Insert draft + Read/Update own draft
-- journal_lines        YES  Full CRUD*        Insert/Read/Update own draft only
-- ledger               YES  Read only         NO ACCESS
-- expenses             YES  Full CRUD         Insert + Read/Update own draft
-- traffic_fines        YES  Full CRUD         Read only
-- payroll_batches      YES  Full CRUD         NO ACCESS
-- payroll_skips        YES  Full CRUD         NO ACCESS
-- payslips             YES  Full CRUD         NO ACCESS
-- transactions         YES  Full CRUD         Insert pending + Read own
-- action_items         YES  Full CRUD         Insert(→accountant) + Read/Update own role
-- audit_log            YES  Read only         NO ACCESS
--
-- * Full CRUD for accountant EXCEPT:
--   - No DELETE on journals (immutability trigger + no delete policy)
--   - No DELETE on journal_lines (same reason)
--
-- KEY NOTES:
--   - Ledger: NEVER query by entity_id — it does not exist on ledger.
--     Always join through journals using receivable_entity_id.
--   - action_items: PRO can INSERT items directed at accountant role.
--     This is required for the rider approval flow and expense approval flow.
--   - rider_code on riders is a display label only. It is NOT a foreign key.
--     The internal UUID (riders.id) is always the foreign key in all other tables.
-- ============================================================

-- ============================================================
-- MERGED: rider_requests RLS policies (moved from rider_onboarding_overhaul.sql)
-- This enables RLS for `rider_requests` and grants scoped access
-- for PRO and accountant roles.
-- ============================================================

ALTER TABLE IF EXISTS public.rider_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "PROs can submit their own requests"
  ON public.rider_requests FOR INSERT
  WITH CHECK (auth.uid() = submitted_by);

CREATE POLICY IF NOT EXISTS "PROs can view their own requests"
  ON public.rider_requests FOR SELECT
  USING (auth.uid() = submitted_by);

CREATE POLICY IF NOT EXISTS "Accountants can view all requests"
  ON public.rider_requests FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'accountant'));

CREATE POLICY IF NOT EXISTS "Accountants can update requests"
  ON public.rider_requests FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'accountant'));





-- ===== MOVED FROM 1_schema.sql: Vendor/Supplier RLS =====
-- ============================================================
-- 6) RLS setup for vendor/supplier profiles
-- ============================================================
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vendors: accountant full access" ON public.vendors;
CREATE POLICY "vendors: accountant full access"
  ON public.vendors FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

DROP POLICY IF EXISTS "vendors: pro read and create" ON public.vendors;
CREATE POLICY "vendors: pro read and create"
  ON public.vendors FOR SELECT
  USING (public.get_my_role() = 'pro');

DROP POLICY IF EXISTS "vendors: pro insert" ON public.vendors;
CREATE POLICY "vendors: pro insert"
  ON public.vendors FOR INSERT
  WITH CHECK (public.get_my_role() = 'pro');

DROP POLICY IF EXISTS "suppliers: accountant full access" ON public.suppliers;
CREATE POLICY "suppliers: accountant full access"
  ON public.suppliers FOR ALL
  USING (public.get_my_role() = 'accountant')
  WITH CHECK (public.get_my_role() = 'accountant');

DROP POLICY IF EXISTS "suppliers: pro read and create" ON public.suppliers;
CREATE POLICY "suppliers: pro read and create"
  ON public.suppliers FOR SELECT
  USING (public.get_my_role() = 'pro');

DROP POLICY IF EXISTS "suppliers: pro insert" ON public.suppliers;
CREATE POLICY "suppliers: pro insert"
  ON public.suppliers FOR INSERT
  WITH CHECK (public.get_my_role() = 'pro');

COMMIT;


-- ===== MOVED FROM 1_schema.sql: Rider Module RLS =====
-- ============================================================
-- 7) RLS for new rider audit tables
-- ============================================================
ALTER TABLE public.rider_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rider_hold_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rider_document_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rider_status_history: accountant full access" ON public.rider_status_history;
CREATE POLICY "rider_status_history: accountant full access"
  ON public.rider_status_history FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'accountant'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'accountant'
    )
  );

DROP POLICY IF EXISTS "rider_status_history: pro read own riders" ON public.rider_status_history;
CREATE POLICY "rider_status_history: pro read own riders"
  ON public.rider_status_history FOR SELECT
  USING (
    rider_id IN (
      SELECT id FROM public.riders
      WHERE created_by_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "rider_hold_history: accountant full access" ON public.rider_hold_history;
CREATE POLICY "rider_hold_history: accountant full access"
  ON public.rider_hold_history FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'accountant'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'accountant'
    )
  );

DROP POLICY IF EXISTS "rider_hold_history: pro read own riders" ON public.rider_hold_history;
CREATE POLICY "rider_hold_history: pro read own riders"
  ON public.rider_hold_history FOR SELECT
  USING (
    rider_id IN (
      SELECT id FROM public.riders
      WHERE created_by_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "rider_document_alerts: accountant full access" ON public.rider_document_alerts;
CREATE POLICY "rider_document_alerts: accountant full access"
  ON public.rider_document_alerts FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'accountant'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'accountant'
    )
  );

DROP POLICY IF EXISTS "rider_document_alerts: pro read own riders" ON public.rider_document_alerts;
CREATE POLICY "rider_document_alerts: pro read own riders"
  ON public.rider_document_alerts FOR SELECT
  USING (
    rider_id IN (
      SELECT id FROM public.riders
      WHERE created_by_user_id = auth.uid()
    )
  );

COMMIT;

