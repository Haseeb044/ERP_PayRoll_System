-- ============================================================
--  RIDER PAYROLL ERP — COMPLETE DATABASE SCHEMA v4.0
--  PostgreSQL / Supabase SQL Editor
--  Fresh database — run this file first, then run 2_rls.sql
--
--  Changes from v3.0:
--    • rider_code column added to riders table
--    • VAT fields added to journals and expenses tables
--    • action_type enum updated with rider_pending_approval
--    • payroll_batch_status enum updated with processing + error
--    • fn_post_journal_to_ledger trigger updated for VAT + expense amount logic
-- ============================================================


-- ============================================================
-- PART 1: ENUM TYPES
-- ============================================================

-- Rider lifecycle status (SRS 2.6)
CREATE TYPE rider_status AS ENUM (
  'active',
  'vacation',
  'retired'
);

-- Bike operational status (SRS 4.2.1)
-- NOTE: default must be 'active' — 'available' does NOT exist here
CREATE TYPE bike_status AS ENUM (
  'active',
  'maintenance',
  'retired'
);

-- Drawer types (SRS 5.2)
CREATE TYPE drawer_type AS ENUM (
  'cash',
  'bank',
  'wallet'
);

-- Journal lifecycle (SRS 1.1.2)
CREATE TYPE journal_status AS ENUM (
  'draft',
  'posted',
  'reversed'
);

-- Journal category (SRS 1.2)
CREATE TYPE journal_type AS ENUM (
  'expense',
  'salary',
  'fine',
  'loan',
  'manual_adjustment'
);

-- Fine lifecycle (SRS 4.9)
CREATE TYPE fine_status AS ENUM (
  'unmatched',
  'matched',
  'assigned',
  'partially_recovered',
  'fully_recovered'
);

-- Payroll batch lifecycle
-- draft     = accountant is reviewing, deductions editable
-- processing = Excel sheet just uploaded, alias matching running
-- error     = processing done but blockers found (alias mismatch etc)
-- finalized = locked, journals posted, drawer deducted
CREATE TYPE payroll_batch_status AS ENUM (
  'draft',
  'processing',
  'error',
  'finalized'
);

-- User roles (SRS 8.2)
CREATE TYPE user_role AS ENUM (
  'accountant',
  'pro'
);

-- Action item severity (SRS 6.2)
CREATE TYPE action_severity AS ENUM (
  'blocker',
  'warning',
  'info'
);

-- Action item type (SRS 6.2)
-- rider_pending_approval = PRO submitted a new rider awaiting accountant review
CREATE TYPE action_type AS ENUM (
  'fine_unmatched',
  'alias_mismatch',
  'journal_pending_approval',
  'rider_pending_approval',
  'insufficient_funds',
  'bike_overlap',
  'duplicate_payslip',
  'other'
);


-- ============================================================
-- PART 2: CORE IDENTITY TABLES
-- ============================================================

-- ----------------------------------------------------------
-- profiles
-- Supabase auth user + role + display info.
-- id = auth.uid() — set when user is created in Supabase Auth.
-- SRS 8.2, 1.5.1.a
-- ----------------------------------------------------------
CREATE TABLE public.profiles (
  id         UUID      NOT NULL DEFAULT auth.uid(),
  email      TEXT      NOT NULL UNIQUE,
  role       user_role NOT NULL DEFAULT 'pro',
  full_name  TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT profiles_pkey PRIMARY KEY (id)
);


-- ----------------------------------------------------------
-- riders
-- Core rider identity. Internal UUID is permanent and never
-- shown externally (SRS 2.1.1).
-- emirates_id_number = unique anchor for audits (SRS 2.1.3).
-- created_by_user_id = which PRO onboarded this rider (SRS 8.4.1).
-- wps_status + release_hold = from salary Excel sheets.
-- rider_code = human-readable 8-char ID shown to users.
--   Format: mix of uppercase letters, numbers, and symbols.
--   Examples: RD#29A7! or A1@B2#C3
--   Auto-generated if not provided. NOT a foreign key anywhere.
-- No assigned_bike / assignment_date — use bike_assignment table.
-- ----------------------------------------------------------
CREATE TABLE public.riders (
  id                  UUID         NOT NULL DEFAULT gen_random_uuid(),
  name                TEXT         NOT NULL,
  emirates_id_number  TEXT         NOT NULL UNIQUE,
  phone               TEXT,
  passport_number     TEXT,
  city                TEXT,
  status              rider_status NOT NULL DEFAULT 'active',
  wps_status          TEXT         NOT NULL DEFAULT 'WPS',      -- 'WPS' | 'Non-WPS'
  release_hold        TEXT         NOT NULL DEFAULT 'release',  -- 'release' | 'hold'
  rider_code          TEXT         UNIQUE,                      -- human-readable 8-char ID
  created_by_user_id  UUID,
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),

  CONSTRAINT riders_pkey PRIMARY KEY (id),

  CONSTRAINT fk_riders_created_by
    FOREIGN KEY (created_by_user_id)
    REFERENCES public.profiles (id),

  CONSTRAINT chk_wps_status
    CHECK (wps_status IN ('WPS', 'Non-WPS')),

  CONSTRAINT chk_release_hold
    CHECK (release_hold IN ('release', 'hold')),

  -- rider_code must be exactly 8 characters if provided
  CONSTRAINT chk_rider_code_length
    CHECK (rider_code IS NULL OR length(rider_code) = 8)
);


-- ----------------------------------------------------------
-- rider_aliases
-- Versioned platform IDs (Talabat ID, Keeta Courier ID).
-- One active alias per platform per rider (SRS 2.2.2).
-- valid_to = NULL means currently active.
-- c3_id = Keeta internal company ID (from Keeta salary sheet).
-- SRS 2.2, 2.3
-- ----------------------------------------------------------
CREATE TABLE public.rider_aliases (
  id                UUID    NOT NULL DEFAULT gen_random_uuid(),
  rider_id          UUID    NOT NULL,
  platform          TEXT    NOT NULL,
  platform_rider_id TEXT    NOT NULL,
  c3_id             TEXT,               -- Keeta C3/internal company ID
  valid_from        DATE    NOT NULL DEFAULT CURRENT_DATE,
  valid_to          DATE,               -- NULL = currently active
  status            TEXT    NOT NULL DEFAULT 'active',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT rider_aliases_pkey PRIMARY KEY (id),

  CONSTRAINT fk_rider_aliases_rider
    FOREIGN KEY (rider_id)
    REFERENCES public.riders (id),

  CONSTRAINT uq_platform_rider_id
    UNIQUE (platform, platform_rider_id),

  CONSTRAINT chk_alias_platform
    CHECK (platform IN ('talabat', 'keeta')),

  CONSTRAINT chk_alias_status
    CHECK (status IN ('active', 'inactive'))
);

-- Partial unique index: only ONE active alias per rider per platform
CREATE UNIQUE INDEX uq_active_alias_per_rider_platform
  ON public.rider_aliases (rider_id, platform)
  WHERE valid_to IS NULL AND status = 'active';


-- ============================================================
-- PART 3: BIKE TABLES
-- ============================================================

-- ----------------------------------------------------------
-- bikes
-- Chassis number IS the primary key (stable hardware unique ID).
-- salik_id links bike to Salik toll tag for fine matching.
-- plate_code = motorcycle category code (from fines sheet).
-- model = optional bike model description.
-- SRS 4.2
-- ----------------------------------------------------------
CREATE TABLE public.bikes (
  bike_id     TEXT        NOT NULL,  -- plate number e.g. DXB-K-12345
  salik_id    TEXT,                  -- optional Salik toll tag ID (manually entered)
  model       TEXT,
  chassis_number TEXT        NOT NULL UNIQUE, -- Unique hardware ID
  status      bike_status NOT NULL DEFAULT 'active',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT bikes_pkey PRIMARY KEY (chassis_number)
);


-- ----------------------------------------------------------
-- bike_assignment
-- Time-based rider ↔ bike assignment.
-- returned_at = NULL means rider currently has the bike.
-- SRS 4.3
-- ----------------------------------------------------------
CREATE TABLE public.bike_assignment (
  id          UUID        NOT NULL DEFAULT gen_random_uuid(),
  chassis_number TEXT      NOT NULL,
  rider_id    UUID        NOT NULL,
  rider_name  TEXT,                  -- denormalised for display speed
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  returned_at TIMESTAMPTZ,           -- NULL = currently assigned

  CONSTRAINT bike_assignment_pkey PRIMARY KEY (id),

  CONSTRAINT fk_bike_assignment_bike
    FOREIGN KEY (chassis_number)
    REFERENCES public.bikes (chassis_number),

  CONSTRAINT fk_bike_assignment_rider
    FOREIGN KEY (rider_id)
    REFERENCES public.riders (id),

  CONSTRAINT chk_assignment_dates
    CHECK (returned_at IS NULL OR returned_at > assigned_at)
);

-- Index for fine matching engine: find who had a bike at a given time
CREATE INDEX idx_bike_assignment_bike_dates
  ON public.bike_assignment (chassis_number, assigned_at, returned_at);

-- Index for currently active assignment queries
CREATE INDEX idx_bike_assignment_active
  ON public.bike_assignment (chassis_number)
  WHERE returned_at IS NULL;


-- ============================================================
-- PART 4: FINANCIAL CORE TABLES
-- ============================================================

-- ----------------------------------------------------------
-- drawer
-- Cash, Bank, Noqodi money containers.
-- balance is CACHED ONLY — truth is in ledger (SRS 5.1.1).
-- SRS 5.2
-- ----------------------------------------------------------
CREATE TABLE public.drawer (
  id          UUID         NOT NULL DEFAULT gen_random_uuid(),
  name        TEXT         NOT NULL UNIQUE,
  type        drawer_type  NOT NULL DEFAULT 'cash',
  currency    TEXT         NOT NULL DEFAULT 'AED',
  balance     NUMERIC      NOT NULL DEFAULT 0,  -- cached, derived from ledger
  color_code  TEXT         NOT NULL DEFAULT '0xFF1F4E79',
  is_active   BOOLEAN      NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),

  CONSTRAINT drawer_pkey PRIMARY KEY (id)
);

-- Seed data — 3 default drawers
INSERT INTO public.drawer (name, type, currency, color_code) VALUES
  ('Cash',   'cash',   'AED', '0xFF2E7D32'),
  ('Bank',   'bank',   'AED', '0xFF1565C0'),
  ('Noqodi', 'wallet', 'AED', '0xFF6A1B9A');


-- ----------------------------------------------------------
-- expense_categories
-- Configurable categories that drive journal default behaviour.
-- default_type = which journal_type this category maps to.
-- SRS 1.2 (Expense Categories)
-- ----------------------------------------------------------
CREATE TABLE public.expense_categories (
  id           UUID         NOT NULL DEFAULT gen_random_uuid(),
  name         TEXT         NOT NULL UNIQUE,
  default_type journal_type NOT NULL DEFAULT 'expense',
  is_active    BOOLEAN      NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),

  CONSTRAINT expense_categories_pkey PRIMARY KEY (id)
);

-- Seed data — restricted to business-approved categories
INSERT INTO public.expense_categories (name, default_type) VALUES
  ('Expense',         'expense'),
  ('Fine',            'fine'),
;

-- Safety cleanup for environments that already have extra categories
DELETE FROM public.expense_categories
WHERE lower(name) NOT IN ('expense', 'fine');


-- ----------------------------------------------------------
-- journal_templates
-- Accountant saves presets to avoid re-entering lines every time.
-- vat_rate here auto-populates VAT rate on expense form when
-- the matching category is selected.
-- SRS 1.5.3
-- ----------------------------------------------------------
CREATE TABLE public.journal_templates (
  id                UUID         NOT NULL DEFAULT gen_random_uuid(),
  name              TEXT         NOT NULL UNIQUE,
  type              journal_type NOT NULL DEFAULT 'expense',
  default_drawer_id UUID,
  category_id       UUID,
  default_accounts  JSONB        NOT NULL DEFAULT '[]',
  vat_rate          NUMERIC      NOT NULL DEFAULT 0,
  is_receivable     BOOLEAN      NOT NULL DEFAULT false,
  is_payable        BOOLEAN      NOT NULL DEFAULT false,
  description       TEXT,
  created_by        UUID,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),

  CONSTRAINT journal_templates_pkey PRIMARY KEY (id),

  CONSTRAINT fk_template_drawer
    FOREIGN KEY (default_drawer_id)
    REFERENCES public.drawer (id),

  CONSTRAINT fk_template_category
    FOREIGN KEY (category_id)
    REFERENCES public.expense_categories (id)
);


-- ----------------------------------------------------------
-- journals
-- THE ROOT OF ALL FINANCIAL EVENTS.
-- Every expense, salary, fine, loan, adjustment MUST have a journal.
-- Deletion is blocked for everyone (no DELETE RLS policy).
-- Posted journals are immutable — only reversal is allowed.
--
-- VAT fields:
--   base_amount = cost before tax
--   vat_rate    = percentage e.g. 5 for 5%
--   vat_amount  = base_amount * vat_rate / 100 (calculated by app)
--   total_amount = base_amount + vat_amount (always stored as final total)
--
-- SRS 1.1, 1.3, 1.5
-- ----------------------------------------------------------
CREATE TABLE public.journals (
  id                     UUID           NOT NULL DEFAULT gen_random_uuid(),
  entry_date             DATE           NOT NULL DEFAULT CURRENT_DATE,
  description            TEXT           NOT NULL,
  total_amount           NUMERIC        NOT NULL DEFAULT 0,  -- base + vat
  base_amount            NUMERIC        NOT NULL DEFAULT 0,  -- cost before VAT
  vat_rate               NUMERIC        NOT NULL DEFAULT 0,  -- VAT percentage
  vat_amount             NUMERIC        NOT NULL DEFAULT 0,  -- calculated VAT
  status                 journal_status NOT NULL DEFAULT 'draft',
  type                   journal_type   NOT NULL DEFAULT 'expense',

  -- Actor attribution (SRS 1.5.1.a) — immutable metadata
  created_by_user_id     UUID,
  created_by_role        user_role      NOT NULL DEFAULT 'pro',
  approved_by            UUID,
  approved_at            TIMESTAMPTZ,

  -- Drawer linkage (SRS 5.5.1) — mandatory on posted journals
  payment_method         TEXT,
  drawer_id              UUID,

  -- Receivable / Payable decision (SRS 1.3.1) — mandatory flag
  is_receivable          BOOLEAN        NOT NULL DEFAULT false,
  is_payable             BOOLEAN        NOT NULL DEFAULT false,
  receivable_entity_type TEXT,          -- 'rider' | 'vendor' | 'supplier'
  receivable_entity_id   UUID,
  receivable_amount      NUMERIC,

  -- Reversal link (SRS 1.1.2)
  reversal_of_journal_id UUID,

  -- Attachment
  receipt_url            TEXT,

  -- Link to individual rider (added for rider statement tracker)
  rider_id               UUID REFERENCES public.riders(id) ON DELETE SET NULL,

  created_at             TIMESTAMPTZ    NOT NULL DEFAULT now(),

  CONSTRAINT journals_pkey PRIMARY KEY (id),

  CONSTRAINT fk_journals_drawer
    FOREIGN KEY (drawer_id)
    REFERENCES public.drawer (id),

  CONSTRAINT fk_journals_created_by
    FOREIGN KEY (created_by_user_id)
    REFERENCES public.profiles (id),

  CONSTRAINT fk_journals_approved_by
    FOREIGN KEY (approved_by)
    REFERENCES public.profiles (id),

  CONSTRAINT fk_journals_reversal
    FOREIGN KEY (reversal_of_journal_id)
    REFERENCES public.journals (id),

  -- Posted journal MUST have drawer + payment_method (SRS 5.5.1, 5.9)
  -- Relaxed for salary accruals and deductions (non-cash)
  CONSTRAINT chk_posted_journal_has_drawer
    CHECK (
      status != 'posted'
      OR (drawer_id IS NOT NULL AND payment_method IS NOT NULL)
      OR (type = 'salary' AND (description ILIKE '%accrual%' OR description ILIKE '%deduction%'))
    ),

  -- VAT consistency: total must equal base + vat
  CONSTRAINT chk_vat_totals
    CHECK (
      total_amount = base_amount + vat_amount
      OR total_amount = 0  -- allow zero during draft creation
    )
);

CREATE INDEX idx_journals_created_by ON public.journals (created_by_user_id);
CREATE INDEX idx_journals_status     ON public.journals (status);
CREATE INDEX idx_journals_entry_date ON public.journals (entry_date);
CREATE INDEX idx_journals_rider_id   ON public.journals (rider_id);


-- ----------------------------------------------------------
-- journal_lines
-- Debit/credit lines for double-entry accounting (SRS 1.1.3).
-- Each line is EITHER a debit OR a credit — never both.
-- SRS 1.1.3
-- ----------------------------------------------------------
CREATE TABLE public.journal_lines (
  id            UUID    NOT NULL DEFAULT gen_random_uuid(),
  journal_id    UUID    NOT NULL,
  account_id    TEXT    NOT NULL,  -- chart of accounts code
  debit_amount  NUMERIC NOT NULL DEFAULT 0,
  credit_amount NUMERIC NOT NULL DEFAULT 0,
  drawer_id     UUID,              -- which drawer this line touches

  CONSTRAINT journal_lines_pkey PRIMARY KEY (id),

  CONSTRAINT fk_journal_lines_journal
    FOREIGN KEY (journal_id)
    REFERENCES public.journals (id),

  CONSTRAINT fk_journal_lines_drawer
    FOREIGN KEY (drawer_id)
    REFERENCES public.drawer (id),

  -- Each line is debit OR credit, never both (SRS 1.1.3)
  CONSTRAINT chk_debit_or_credit
    CHECK (
      debit_amount  >= 0 AND
      credit_amount >= 0 AND
      NOT (debit_amount > 0 AND credit_amount > 0)
    )
);

CREATE INDEX idx_journal_lines_journal_id ON public.journal_lines (journal_id);


-- ----------------------------------------------------------
-- ledger
-- READ-ONLY audit trail. Never insert manually.
-- Written ONLY by trigger when journal status → posted.
-- Trigger logic:
--   If journal has a linked expense → use expense original amount
--   If VAT > 0 → insert extra row with account_id = 'vat_payable'
--   If no linked expense → use journal line amounts
-- SRS 1.2
-- ----------------------------------------------------------
CREATE TABLE public.ledger (
  id               UUID    NOT NULL DEFAULT gen_random_uuid(),
  journal_id       UUID    NOT NULL,
  journal_line_id  UUID    NOT NULL,
  account_id       TEXT    NOT NULL,
  debit_amount     NUMERIC NOT NULL DEFAULT 0,
  credit_amount    NUMERIC NOT NULL DEFAULT 0,
  posted_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT ledger_pkey PRIMARY KEY (id),

  CONSTRAINT fk_ledger_journal
    FOREIGN KEY (journal_id)
    REFERENCES public.journals (id),

  CONSTRAINT fk_ledger_journal_line
    FOREIGN KEY (journal_line_id)
    REFERENCES public.journal_lines (id)
);

CREATE INDEX idx_ledger_journal_id ON public.ledger (journal_id);
CREATE INDEX idx_ledger_account_id ON public.ledger (account_id);


-- ============================================================
-- PART 5: EXPENSE & FINE TABLES
-- ============================================================

-- ----------------------------------------------------------
-- expenses
-- PRO-facing journal creation interface.
-- journal_id links to the root journal.
-- Draft journal is created simultaneously with the expense row.
--
-- VAT fields mirror journals table:
--   base_amount = what the PRO typed as the cost
--   vat_rate    = auto-populated from journal_templates
--   vat_amount  = calculated by app (base * rate / 100)
--   amount      = base + vat (final total stored here)
--
-- SRS 1.2, 8.2.2, 9.2
-- ----------------------------------------------------------
CREATE TABLE public.expenses (
  id              UUID        NOT NULL DEFAULT gen_random_uuid(),
  rider_id        UUID,
  rider_name      TEXT,                 -- denormalised for display
  expense_type    TEXT        NOT NULL,
  category_id     UUID,
  amount          NUMERIC     NOT NULL CHECK (amount > 0),  -- total incl. VAT
  base_amount     NUMERIC     NOT NULL DEFAULT 0,           -- cost before VAT
  vat_rate        NUMERIC     NOT NULL DEFAULT 0,           -- VAT percentage
  vat_amount      NUMERIC     NOT NULL DEFAULT 0,           -- calculated VAT
  expense_date    DATE        NOT NULL,
  description     TEXT,
  status          TEXT        NOT NULL DEFAULT 'pending',
  journal_id      UUID,
  receipt_url     TEXT,
  created_by_role TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),

  CONSTRAINT expenses_pkey PRIMARY KEY (id),

  CONSTRAINT fk_expenses_rider
    FOREIGN KEY (rider_id)
    REFERENCES public.riders (id),

  CONSTRAINT fk_expenses_journal
    FOREIGN KEY (journal_id)
    REFERENCES public.journals (id),

  CONSTRAINT fk_expenses_category
    FOREIGN KEY (category_id)
    REFERENCES public.expense_categories (id),

  CONSTRAINT chk_expense_status
    CHECK (status IN ('pending', 'approved', 'rejected')),

  -- VAT consistency
  CONSTRAINT chk_expense_vat_totals
    CHECK (amount = base_amount + vat_amount OR base_amount = 0)
);

CREATE INDEX idx_expenses_rider_id   ON public.expenses (rider_id);
CREATE INDEX idx_expenses_journal_id ON public.expenses (journal_id);


-- ----------------------------------------------------------
-- traffic_fines
-- Ingested from Excel upload or manual entry.
-- Matched to rider via bike_assignment date-range lookup.
-- SRS 4.4, 4.5, 4.9
-- ----------------------------------------------------------
CREATE TABLE public.traffic_fines (
  id             UUID        NOT NULL DEFAULT gen_random_uuid(),
  ticket_number  TEXT        NOT NULL UNIQUE,
  plate_number   TEXT        NOT NULL,
  violation_date TIMESTAMPTZ NOT NULL,
  ticket_time    TEXT,                          -- e.g. '06:46 AM'
  amount         NUMERIC     NOT NULL,
  plus_amount    NUMERIC     NOT NULL DEFAULT 0, -- additional penalty
  type           TEXT        NOT NULL DEFAULT 'other',
  fines_source   TEXT,                           -- 'Dubai Police', 'RTA', etc.
  aggregator     TEXT,                           -- 'Talabat' | 'Keeta'
  description    TEXT,
  city           TEXT                 DEFAULT 'Dubai',
  image_url      TEXT,
  rider_id       UUID,
  rider_name     TEXT,
  status         fine_status NOT NULL DEFAULT 'unmatched',
  journal_id     UUID,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT traffic_fines_pkey PRIMARY KEY (id),

  CONSTRAINT fk_fines_rider
    FOREIGN KEY (rider_id)
    REFERENCES public.riders (id),

  CONSTRAINT fk_fines_journal
    FOREIGN KEY (journal_id)
    REFERENCES public.journals (id)
);

CREATE INDEX idx_fines_plate_date ON public.traffic_fines (plate_number, violation_date);
CREATE INDEX idx_fines_status     ON public.traffic_fines (status);
CREATE INDEX idx_fines_rider_id   ON public.traffic_fines (rider_id);


-- ============================================================
-- PART 6: PAYROLL TABLES
-- ============================================================

-- ----------------------------------------------------------
-- payroll_batches
-- One batch per platform per month.
-- UNIQUE(month, platform) blocks duplicate uploads (SRS 3.1.2).
-- Status flow: processing → draft → finalized
--              processing → error → (fix blockers) → draft → finalized
-- SRS 3.1, 3.2
-- ----------------------------------------------------------
CREATE TABLE public.payroll_batches (
  id           UUID                 NOT NULL DEFAULT gen_random_uuid(),
  month        TEXT                 NOT NULL, -- 'YYYY-MM' e.g. '2025-12'
  platform     TEXT                 NOT NULL, -- 'talabat' | 'keeta'
  status       payroll_batch_status NOT NULL DEFAULT 'draft',
  total_amount NUMERIC              NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ          NOT NULL DEFAULT timezone('utc', now()),

  CONSTRAINT payroll_batches_pkey PRIMARY KEY (id),

  CONSTRAINT uq_batch_month_platform UNIQUE (month, platform)
);


-- ----------------------------------------------------------
-- payslips
-- One payslip per rider per batch (SRS 3.1.2).
-- rider_alias_id = alias that was ACTIVE at payroll time.
-- SRS 3.3, 3.6, 3.9
-- ----------------------------------------------------------
CREATE TABLE public.payslips (
  id                   UUID    NOT NULL DEFAULT gen_random_uuid(),
  batch_id             UUID,
  rider_id             UUID,
  rider_alias_id       UUID,
  rider_name           TEXT    NOT NULL DEFAULT '',
  external_id          TEXT    NOT NULL DEFAULT '',

  -- Earnings
  gross_salary         NUMERIC NOT NULL DEFAULT 0,
  arears               NUMERIC NOT NULL DEFAULT 0,
  tds_bonus            NUMERIC NOT NULL DEFAULT 0,
  food_compensation    NUMERIC NOT NULL DEFAULT 0,
  tips                 NUMERIC NOT NULL DEFAULT 0,
  online_hours         NUMERIC NOT NULL DEFAULT 0,
  order_count          INTEGER NOT NULL DEFAULT 0,

  -- Platform deductions (read-only from sheet)
  platform_deductions  NUMERIC NOT NULL DEFAULT 0,
  cod_deficit          NUMERIC NOT NULL DEFAULT 0,
  clawback_deduction   NUMERIC NOT NULL DEFAULT 0,

  -- Company deductions (internal)
  internal_fines       NUMERIC NOT NULL DEFAULT 0,
  internal_expenses    NUMERIC NOT NULL DEFAULT 0,
  other_deductions     NUMERIC NOT NULL DEFAULT 0,

  -- Totals
  total_expenses       NUMERIC NOT NULL DEFAULT 0,
  total_fines          NUMERIC NOT NULL DEFAULT 0,
  net_salary           NUMERIC NOT NULL DEFAULT 0,
  prev_balance         NUMERIC NOT NULL DEFAULT 0,
  wps_batch            TEXT,

  -- Raw data
  platform_data        JSONB   NOT NULL DEFAULT '{}',
  items                JSONB   NOT NULL DEFAULT '[]',

  -- Match status
  status               TEXT    NOT NULL DEFAULT 'mismatch', -- 'matched' | 'mismatch' | 'error' | 'finalized'
  error_reason         TEXT,
  review_required      BOOLEAN NOT NULL DEFAULT false,
  issue_codes          JSONB   NOT NULL DEFAULT '[]',
  issue_snapshot       JSONB   NOT NULL DEFAULT '{}',
  adjusted_at          TIMESTAMPTZ,
  adjusted_by          UUID,

  -- Link to individual generation journal (added for individual review flow)
  journal_id           UUID,

  created_at           TIMESTAMPTZ DEFAULT now(),

  CONSTRAINT payslips_pkey PRIMARY KEY (id),

  CONSTRAINT fk_payslips_batch
    FOREIGN KEY (batch_id)
    REFERENCES public.payroll_batches (id),

  CONSTRAINT fk_payslips_rider
    FOREIGN KEY (rider_id)
    REFERENCES public.riders (id),

  CONSTRAINT fk_payslips_alias
    FOREIGN KEY (rider_alias_id)
    REFERENCES public.rider_aliases (id),

  CONSTRAINT chk_payslip_status
    CHECK (status IN ('matched', 'mismatch', 'error', 'finalized')),

  CONSTRAINT fk_payslips_journal
    FOREIGN KEY (journal_id)
    REFERENCES public.journals (id),

  CONSTRAINT fk_payslips_adjusted_by
    FOREIGN KEY (adjusted_by)
    REFERENCES public.profiles (id)
);

CREATE INDEX idx_payslips_rider_id ON public.payslips (rider_id);
CREATE INDEX idx_payslips_batch_id ON public.payslips (batch_id);


-- ============================================================
-- PART 7: TRANSACTION & ACTION TABLES
-- ============================================================

-- ----------------------------------------------------------
-- transactions
-- PRO-initiated cash advance / payment requests.
-- SRS 8.2.2
-- ----------------------------------------------------------
CREATE TABLE public.transactions (
  id         UUID        NOT NULL DEFAULT gen_random_uuid(),
  drawer_id  UUID        NOT NULL,
  rider_id   UUID        NOT NULL,
  amount     NUMERIC     NOT NULL CHECK (amount > 0),
  status     TEXT        NOT NULL DEFAULT 'pending',
  reason     TEXT        NOT NULL,
  journal_id UUID,
  created_at TIMESTAMPTZ DEFAULT now(),

  CONSTRAINT transactions_pkey PRIMARY KEY (id),

  CONSTRAINT fk_transactions_drawer
    FOREIGN KEY (drawer_id)
    REFERENCES public.drawer (id),

  CONSTRAINT fk_transactions_rider
    FOREIGN KEY (rider_id)
    REFERENCES public.riders (id),

  CONSTRAINT fk_transactions_journal
    FOREIGN KEY (journal_id)
    REFERENCES public.journals (id),

  CONSTRAINT chk_transaction_status
    CHECK (status IN ('pending', 'approved', 'rejected'))
);


-- ----------------------------------------------------------
-- action_items
-- System notifications that cannot auto-disappear (SRS 6.6.1).
-- Types:
--   fine_unmatched         = fine uploaded but no rider found
--   alias_mismatch         = salary sheet rider ID not in aliases
--   journal_pending_approval = PRO submitted expense awaiting accountant
--   rider_pending_approval = PRO created rider awaiting accountant completion
--   insufficient_funds     = drawer balance too low
--   bike_overlap           = overlapping bike assignment detected
--   duplicate_payslip      = attempt to create second payslip for same rider/month
--   other                  = general notification
-- SRS 6.2, 6.6, 6.7
-- ----------------------------------------------------------
CREATE TABLE public.action_items (
  id                UUID            NOT NULL DEFAULT gen_random_uuid(),
  type              action_type     NOT NULL DEFAULT 'other',
  title             TEXT            NOT NULL,
  subtitle          TEXT            NOT NULL DEFAULT '',
  severity          action_severity NOT NULL DEFAULT 'warning',
  route             TEXT            NOT NULL DEFAULT '',  -- deep link in Flutter app
  argument_id       UUID,                                -- entity to navigate to
  related_entity    TEXT,                                -- 'rider'|'journal'|'bike'|'drawer'
  reference_id      UUID,                                -- UUID of the related entity
  responsible_role  user_role,                           -- who must act
  resolved_by       UUID,
  resolution_notes  TEXT,
  resolved_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ     NOT NULL DEFAULT now(),

  CONSTRAINT action_items_pkey PRIMARY KEY (id),

  CONSTRAINT fk_action_items_resolved_by
    FOREIGN KEY (resolved_by)
    REFERENCES public.profiles (id)
);

-- Fast query for open (unresolved) items
CREATE INDEX idx_action_items_open
  ON public.action_items (responsible_role, created_at)
  WHERE resolved_at IS NULL;

-- Fast query by reference entity
CREATE INDEX idx_action_items_reference
  ON public.action_items (reference_id)
  WHERE resolved_at IS NULL;


-- ============================================================
-- PART 8: AUDIT LOG
-- ============================================================

CREATE TABLE public.audit_log (
  id                  UUID        NOT NULL DEFAULT gen_random_uuid(),
  table_name          TEXT        NOT NULL,
  record_id           UUID        NOT NULL,
  action              TEXT        NOT NULL,
  old_data            JSONB,
  new_data            JSONB,
  changed_by_user_id  UUID,
  changed_at          TIMESTAMPTZ DEFAULT now(),

  CONSTRAINT audit_log_pkey PRIMARY KEY (id),

  CONSTRAINT chk_audit_action
    CHECK (action IN ('INSERT', 'UPDATE', 'DELETE'))
);

CREATE INDEX idx_audit_log_table_record ON public.audit_log (table_name, record_id);
CREATE INDEX idx_audit_log_changed_at   ON public.audit_log (changed_at);


-- ============================================================
-- PART 9: TRIGGERS
-- ============================================================

-- ----------------------------------------------------------
-- Trigger 1: Block editing or deleting posted/reversed journals
-- SRS 1.1.2 — Posted journals are immutable
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_block_posted_journal_changes()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- If journal is already posted/reversed, restrict modifications
  IF OLD.status IN ('posted', 'reversed') THEN
    
    -- 1. Allow status update from 'posted' -> 'reversed' (Accounting Correction)
    IF NEW.status = 'reversed' AND OLD.status = 'posted' THEN
      RETURN NEW;
    END IF;

    -- 2. Block Deletions
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'Posted/reversed journals cannot be deleted. Create a reversal journal instead.';
    END IF;

    -- 3. Block all other edits
    RAISE EXCEPTION 'Posted journals cannot be edited. Status was %. Only Reversal is allowed.', OLD.status;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_journal_immutability
  BEFORE UPDATE OR DELETE ON public.journals
  FOR EACH ROW EXECUTE FUNCTION fn_block_posted_journal_changes();


-- ----------------------------------------------------------
-- Trigger 2: Verify debits = credits before posting
-- SRS 1.1.3 — Double-entry enforcement
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_check_journal_balance()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_total_debit  NUMERIC;
  v_total_credit NUMERIC;
BEGIN
  IF NEW.status = 'posted' AND OLD.status = 'draft' THEN
    SELECT
      COALESCE(SUM(debit_amount),  0),
      COALESCE(SUM(credit_amount), 0)
    INTO v_total_debit, v_total_credit
    FROM public.journal_lines
    WHERE journal_id = NEW.id;

    IF v_total_debit != v_total_credit THEN
      RAISE EXCEPTION
        'Journal imbalanced: debits (%) ≠ credits (%). Cannot post.',
        v_total_debit, v_total_credit;
    END IF;

    IF v_total_debit = 0 THEN
      RAISE EXCEPTION 'Journal has no lines. Cannot post.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_journal_balance_check
  BEFORE UPDATE ON public.journals
  FOR EACH ROW EXECUTE FUNCTION fn_check_journal_balance();


-- ----------------------------------------------------------
-- Trigger 3: Write ledger rows when journal is posted
-- Updated logic:
--   - If journal has a linked expense → use expense original amounts
--   - If VAT amount > 0 → insert extra vat_payable ledger row
--   - If no linked expense → fall back to journal line amounts
--   - Result: debit(base) + debit(vat) = credit(total) always
-- SRS 1.2
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_post_journal_to_ledger()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_expense_id         UUID;
  v_expense_amount     NUMERIC;
  v_expense_vat_amount NUMERIC;
  v_expense_base       NUMERIC;
  v_rider_id           UUID;
BEGIN
  IF NEW.status = 'posted' AND OLD.status = 'draft' THEN

    -- Check if a linked expense exists for this journal
    SELECT id, amount, vat_amount, base_amount
    INTO v_expense_id, v_expense_amount, v_expense_vat_amount, v_expense_base
    FROM public.expenses
    WHERE journal_id = NEW.id
    LIMIT 1;

    IF v_expense_id IS NOT NULL THEN
      -- Try to capture rider from the linked expense for easier rider-ledger queries
      SELECT rider_id INTO v_rider_id FROM public.expenses WHERE id = v_expense_id LIMIT 1;
      -- Expense exists — use original expense amounts in ledger
      -- Debit lines → base_amount (cost before VAT)
      -- Credit lines → full amount including VAT
      INSERT INTO public.ledger (
        journal_id, journal_line_id, account_id,
        debit_amount, credit_amount, rider_id
      )
      SELECT
        jl.journal_id,
        jl.id,
        jl.account_id,
        CASE WHEN jl.debit_amount > 0
          THEN COALESCE(v_expense_base, v_expense_amount)
          ELSE 0
        END,
        CASE WHEN jl.credit_amount > 0
          THEN COALESCE(v_expense_amount, 0)
          ELSE 0
        END,
        v_rider_id
      FROM public.journal_lines jl
      WHERE jl.journal_id = NEW.id;

      -- If VAT exists insert a separate vat_payable ledger row
      -- This ensures: debit(base) + debit(vat) = credit(total) ✓
      IF COALESCE(v_expense_vat_amount, 0) > 0 THEN
        INSERT INTO public.ledger (
          journal_id, journal_line_id, account_id,
          debit_amount, credit_amount, rider_id
        )
        SELECT
          NEW.id,
          jl.id,
          'vat_payable',
          v_expense_vat_amount,
          0,
          v_rider_id
        FROM public.journal_lines jl
        WHERE jl.journal_id = NEW.id
          AND jl.debit_amount > 0
        LIMIT 1;
      END IF;

    ELSE
      -- No linked expense — direct accountant journal
      -- Use journal line amounts as-is
      -- No linked expense — attempt to capture rider from journal receivable entity
      IF NEW.receivable_entity_type = 'rider' AND NEW.receivable_entity_id IS NOT NULL THEN
        v_rider_id := NEW.receivable_entity_id;
      END IF;

      INSERT INTO public.ledger (
        journal_id, journal_line_id, account_id,
        debit_amount, credit_amount, rider_id
      )
      SELECT
        jl.journal_id,
        jl.id,
        jl.account_id,
        jl.debit_amount,
        jl.credit_amount,
        v_rider_id
      FROM public.journal_lines jl
      WHERE jl.journal_id = NEW.id;

    END IF;

  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_post_journal_to_ledger
  AFTER UPDATE ON public.journals
  FOR EACH ROW EXECUTE FUNCTION fn_post_journal_to_ledger();


-- ----------------------------------------------------------
-- Trigger 4: Block activity for retired riders
-- Covers both journals and payslips in one function.
-- SRS 2.6 — Retired riders are frozen
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_block_retired_rider_activity()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME = 'journals' THEN
    IF NEW.receivable_entity_type = 'rider'
       AND NEW.receivable_entity_id IS NOT NULL THEN
      IF EXISTS (
        SELECT 1 FROM public.riders
        WHERE id = NEW.receivable_entity_id
          AND status = 'retired'
      ) THEN
        RAISE EXCEPTION
          'Cannot create or update journal for a retired rider. Rider ID: %.',
          NEW.receivable_entity_id;
      END IF;
    END IF;

  ELSIF TG_TABLE_NAME = 'payslips' THEN
    IF NEW.rider_id IS NOT NULL THEN
      IF EXISTS (
        SELECT 1 FROM public.riders
        WHERE id = NEW.rider_id
          AND status = 'retired'
      ) THEN
        RAISE EXCEPTION
          'Cannot create or update payslip for a retired rider. Rider ID: %.',
          NEW.rider_id;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_block_retired_rider_journal
  BEFORE INSERT OR UPDATE ON public.journals
  FOR EACH ROW EXECUTE FUNCTION fn_block_retired_rider_activity();

CREATE TRIGGER trg_block_retired_rider_payslip
  BEFORE INSERT OR UPDATE ON public.payslips
  FOR EACH ROW EXECUTE FUNCTION fn_block_retired_rider_activity();


-- ----------------------------------------------------------
-- Trigger 5: Protect retired bike history from deletion
-- SRS 4.2.1 — Retired bikes are permanently archived
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_protect_retired_bike_history()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_assignment_count INT;
  v_fine_count       INT;
BEGIN
  IF OLD.status = 'retired' THEN
    SELECT COUNT(*) INTO v_assignment_count
    FROM public.bike_assignment
    WHERE chassis_number = OLD.chassis_number;

    SELECT COUNT(*) INTO v_fine_count
    FROM public.traffic_fines
    WHERE plate_number = OLD.bike_id;

    IF v_assignment_count > 0 OR v_fine_count > 0 THEN
      RAISE EXCEPTION
        'Retired bike % cannot be deleted. It has % assignment records and % fine records. Financial history must be preserved for audit purposes.',
        OLD.bike_id, v_assignment_count, v_fine_count;
    END IF;
  END IF;
  RETURN OLD;
END;
$$;

CREATE TRIGGER trg_protect_retired_bike_deletion
  BEFORE DELETE ON public.bikes
  FOR EACH ROW EXECUTE FUNCTION fn_protect_retired_bike_history();


-- ============================================================
-- DONE
--
-- Tables (18):
--   profiles, riders, rider_aliases
--   bikes, bike_assignment
--   drawer, expense_categories, journal_templates
--   journals, journal_lines, ledger
--   expenses, traffic_fines
--   payroll_batches, payslips
--   transactions, action_items, audit_log
--
-- Enum types (10):
--   rider_status, bike_status, drawer_type
--   journal_status, journal_type, fine_status
--   payroll_batch_status, user_role
--   action_severity, action_type
--
-- Triggers (5 functions, 6 trigger instances):
--   trg_journal_immutability          (journals)
--   trg_journal_balance_check         (journals)
--   trg_post_journal_to_ledger        (journals)
--   trg_block_retired_rider_journal   (journals)
--   trg_block_retired_rider_payslip   (payslips)
--   trg_protect_retired_bike_deletion (bikes)
--
-- Indexes (14 total)
--
-- Seed data:
--   3 drawers  (Cash, Bank, Noqodi)
--   13 expense categories
--
-- Changes from v3.0:
--   + rider_code TEXT UNIQUE on riders
--   + chk_wps_status, chk_release_hold, chk_rider_code_length constraints
--   + base_amount, vat_rate, vat_amount on journals
--   + chk_vat_totals constraint on journals
--   + base_amount, vat_rate, vat_amount on expenses
--   + chk_expense_vat_totals constraint on expenses
--   + payroll_batch_status now includes 'processing' and 'error'
--   + action_type now includes 'rider_pending_approval'
--   + fn_post_journal_to_ledger updated with VAT + expense amount logic
--   + action_items indexes improved (open items + reference_id)
-- ============================================================

-- ============================================================
-- MERGED: Additional migrations, triggers, and RPCs
-- This section consolidates standalone migration and RPC files
-- into the primary `1_schema.sql` for a single-schema deployment.
-- Statements use idempotent forms (IF NOT EXISTS / CREATE OR REPLACE)
-- where appropriate so this file can be re-run safely.
-- ============================================================

-- ===== add_drawer_balance_trigger.sql =====
CREATE OR REPLACE FUNCTION fn_update_drawer_balance()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.status = 'posted' AND OLD.status = 'draft' THEN
    UPDATE public.drawer d
    SET balance = d.balance + 
                 (SELECT COALESCE(SUM(jl.debit_amount - jl.credit_amount), 0)
                  FROM public.journal_lines jl
                  WHERE jl.journal_id = NEW.id 
                    AND jl.drawer_id = d.id)
    WHERE d.id IN (
      SELECT drawer_id 
      FROM public.journal_lines 
      WHERE journal_id = NEW.id AND drawer_id IS NOT NULL
    );
  ELSIF NEW.status = 'reversed' AND OLD.status = 'posted' THEN
    UPDATE public.drawer d
    SET balance = d.balance - 
                 (SELECT COALESCE(SUM(jl.debit_amount - jl.credit_amount), 0)
                  FROM public.journal_lines jl
                  WHERE jl.journal_id = NEW.id 
                    AND jl.drawer_id = d.id)
    WHERE d.id IN (
      SELECT drawer_id 
      FROM public.journal_lines 
      WHERE journal_id = NEW.id AND drawer_id IS NOT NULL
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_drawer_balance ON public.journals;
CREATE TRIGGER trg_update_drawer_balance
  AFTER UPDATE OF status ON public.journals
  FOR EACH ROW 
  EXECUTE FUNCTION fn_update_drawer_balance();

-- ===== add_remaining_balance_to_fines.sql =====
ALTER TABLE IF EXISTS public.traffic_fines 
  ADD COLUMN IF NOT EXISTS remaining_balance NUMERIC;
UPDATE public.traffic_fines 
SET remaining_balance = amount 
WHERE remaining_balance IS NULL;

-- ===== add_rider_id_to_ledger.sql =====
ALTER TABLE IF EXISTS public.ledger
  ADD COLUMN IF NOT EXISTS rider_id UUID;
CREATE INDEX IF NOT EXISTS idx_ledger_rider_id ON public.ledger (rider_id);

-- ===== database_migration_constraints.sql (selected idempotent changes) =====
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_alias
  ON public.rider_aliases (platform, platform_rider_id)
  WHERE valid_to IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_batch_month_platform'
  ) THEN
    ALTER TABLE public.payroll_batches
      ADD CONSTRAINT uq_batch_month_platform UNIQUE (month, platform);
  END IF;
END $$;

ALTER TABLE IF EXISTS public.payslips
  ADD COLUMN IF NOT EXISTS review_required BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS issue_codes JSONB NOT NULL DEFAULT '[]'::JSONB,
  ADD COLUMN IF NOT EXISTS issue_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  ADD COLUMN IF NOT EXISTS adjusted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS adjusted_by UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_payslips_adjusted_by'
  ) THEN
    ALTER TABLE public.payslips
      ADD CONSTRAINT fk_payslips_adjusted_by
      FOREIGN KEY (adjusted_by) REFERENCES public.profiles(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_payslips_review_required
  ON public.payslips (review_required)
  WHERE review_required = true;

CREATE INDEX IF NOT EXISTS idx_payslips_batch_id
  ON public.payslips (batch_id);

CREATE INDEX IF NOT EXISTS idx_payslips_rider_id
  ON public.payslips (rider_id);

CREATE INDEX IF NOT EXISTS idx_traffic_fines_rider_status
  ON public.traffic_fines (rider_id, status);

CREATE INDEX IF NOT EXISTS idx_expenses_rider_status
  ON public.expenses (rider_id, status);

CREATE INDEX IF NOT EXISTS idx_rider_aliases_platform_id_status
  ON public.rider_aliases (platform, platform_rider_id, status);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_debit_or_credit'
  ) THEN
    ALTER TABLE public.journal_lines
      ADD CONSTRAINT chk_debit_or_credit
      CHECK (NOT (debit_amount > 0 AND credit_amount > 0));
  END IF;
END $$;

CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE IF EXISTS public.bike_assignment
  ADD CONSTRAINT IF NOT EXISTS no_overlap_bike_assignment
  EXCLUDE USING gist (
    chassis_number WITH =,
    tstzrange(assigned_at, COALESCE(returned_at, 'infinity'::timestamptz)) WITH &&
  );

-- Ensure ledger auto-populate trigger exists (idempotent CREATE OR REPLACE in case migration used older name)
CREATE OR REPLACE FUNCTION public.fn_journal_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.status = 'posted' AND (OLD.status IS DISTINCT FROM 'posted') THEN
    INSERT INTO public.ledger (journal_id, journal_line_id, account_id, debit_amount, credit_amount, posted_at)
    SELECT
      NEW.id,
      jl.id,
      jl.account_id,
      jl.debit_amount,
      jl.credit_amount,
      now()
    FROM public.journal_lines jl
    WHERE jl.journal_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_journal_post_to_ledger ON public.journals;
CREATE TRIGGER trg_journal_post_to_ledger
  AFTER UPDATE ON public.journals
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_journal_to_ledger();

-- ===== fix_salik_id_migration.sql =====
ALTER TABLE IF EXISTS public.bikes DROP CONSTRAINT IF EXISTS uq_bikes_salik_id;
ALTER TABLE IF EXISTS public.bikes
  ALTER COLUMN salik_id DROP DEFAULT,
  ALTER COLUMN salik_id DROP NOT NULL,
  ALTER COLUMN salik_id TYPE TEXT USING salik_id::TEXT;

-- ===== fix_ledger_rls_trigger.sql (ensure security definer & updated function) =====
CREATE OR REPLACE FUNCTION public.fn_post_journal_to_ledger()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_expense_id         UUID;
  v_expense_vat_amount NUMERIC;
  v_rider_id           UUID;
  v_has_vat_line       BOOLEAN := FALSE;
BEGIN
  IF NEW.status = 'posted' AND OLD.status = 'draft' THEN

    SELECT id, vat_amount
    INTO v_expense_id, v_expense_vat_amount
    FROM public.expenses
    WHERE journal_id = NEW.id
    LIMIT 1;

    IF v_expense_id IS NOT NULL THEN
      SELECT rider_id INTO v_rider_id
      FROM public.expenses
      WHERE id = v_expense_id
      LIMIT 1;
    ELSIF NEW.receivable_entity_type = 'rider' AND NEW.receivable_entity_id IS NOT NULL THEN
      v_rider_id := NEW.receivable_entity_id;
    END IF;

    -- Always post explicit journal lines exactly as entered.
    INSERT INTO public.ledger (
      journal_id, journal_line_id, account_id,
      debit_amount, credit_amount, rider_id
    )
    SELECT
      jl.journal_id,
      jl.id,
      jl.account_id,
      jl.debit_amount,
      jl.credit_amount,
      v_rider_id
    FROM public.journal_lines jl
    WHERE jl.journal_id = NEW.id;

    -- Auto-add VAT row only for legacy expense journals that do not include vat_payable line.
    IF v_expense_id IS NOT NULL AND COALESCE(v_expense_vat_amount, 0) > 0 THEN
      SELECT EXISTS (
        SELECT 1
        FROM public.journal_lines jl
        WHERE jl.journal_id = NEW.id
          AND lower(COALESCE(jl.account_id, '')) = 'vat_payable'
      ) INTO v_has_vat_line;

      IF NOT v_has_vat_line THEN
        INSERT INTO public.ledger (
          journal_id, journal_line_id, account_id,
          debit_amount, credit_amount, rider_id
        )
        SELECT
          NEW.id,
          jl.id,
          'vat_payable',
          v_expense_vat_amount,
          0,
          v_rider_id
        FROM public.journal_lines jl
        WHERE jl.journal_id = NEW.id
          AND jl.debit_amount > 0
        LIMIT 1;
      END IF;
    END IF;

  END IF;
  RETURN NEW;
END;
$$;

-- ===== rpc_upload_payroll.sql (merged RPC) =====
CREATE OR REPLACE FUNCTION public.rpc_upload_payroll_batch(
  p_month            TEXT,
  p_platform         TEXT,
  p_total_amount     NUMERIC,
  p_payslips         JSONB[],
  p_rider_aliases    JSONB[],
  p_expenses         JSONB[],
  p_action_items     JSONB[]
)
LANGUAGE plpgsql
SECURITY DEFINER 
SET search_path = public
AS $$
DECLARE
  v_batch_id UUID;
  v_payslip_row JSONB;
  v_inserted_payslip_id UUID;
  v_external_id TEXT;
  v_result JSONB;
  v_user_role TEXT;
BEGIN
  v_user_role := public.get_my_role();
  IF v_user_role != 'accountant' THEN
    RAISE EXCEPTION 'Unauthorized: Only accountants can upload payroll. (Detected Role: %, UID: %)', 
      COALESCE(v_user_role, 'no row'), auth.uid();
  END IF;

  INSERT INTO public.payroll_batches (month, platform, status, total_amount)
  VALUES (p_month, p_platform, 'draft', p_total_amount)
  RETURNING id INTO v_batch_id;

  FOR i IN 1 .. COALESCE(array_length(p_payslips, 1), 0) LOOP
    INSERT INTO public.payslips (
      batch_id, 
      rider_id, rider_alias_id, rider_name, external_id,
      gross_salary, arears, tds_bonus, food_compensation, tips, online_hours, order_count,
      platform_deductions, cod_deficit, clawback_deduction,
      internal_fines, internal_expenses, other_deductions,
      total_expenses, total_fines, net_salary, prev_balance, wps_batch,
      platform_data, items, status, error_reason,
      review_required, issue_codes, issue_snapshot
    )
    SELECT 
      v_batch_id,
      ((p_payslips[i]->>'rider_id')::UUID),
      ((p_payslips[i]->>'rider_alias_id')::UUID),
      (p_payslips[i]->>'rider_name'),
      (p_payslips[i]->>'external_id'),
      (COALESCE((p_payslips[i]->>'gross_salary')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'arears')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'tds_bonus')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'food_compensation')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'tips')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'online_hours')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'order_count')::INTEGER, 0)),
      (COALESCE((p_payslips[i]->>'platform_deductions')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'cod_deficit')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'clawback_deduction')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'internal_fines')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'internal_expenses')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'other_deductions')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'total_expenses')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'total_fines')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'net_salary')::NUMERIC, 0)),
      (COALESCE((p_payslips[i]->>'prev_balance')::NUMERIC, 0)),
      (p_payslips[i]->>'wps_batch'),
      (COALESCE((p_payslips[i]->'platform_data'), '{}'::JSONB)),
      (COALESCE((p_payslips[i]->'items'), '[]'::JSONB)),
      (COALESCE((p_payslips[i]->>'status'), 'mismatch')),
      (p_payslips[i]->>'error_reason'),
      (COALESCE((p_payslips[i]->>'review_required')::BOOLEAN, false)),
      (COALESCE((p_payslips[i]->'issue_codes'), '[]'::JSONB)),
      (COALESCE((p_payslips[i]->'issue_snapshot'), '{}'::JSONB))
    RETURNING id INTO v_inserted_payslip_id;
  END LOOP;

  RETURN jsonb_build_object(
    'batch_id', v_batch_id,
    'payslips_count', COALESCE(array_length(p_payslips, 1), 0)
  );
END;
$$;

-- ===== rpc_create_rider_with_action.sql =====
CREATE OR REPLACE FUNCTION rpc_create_rider_with_action(
    p_rider_code TEXT,
    p_name TEXT,
    p_emirates_id_number TEXT,
    p_phone TEXT,
    p_passport_number TEXT,
    p_city TEXT,
    p_created_by_user_id UUID,
    p_action_severity TEXT DEFAULT 'warning'
)
RETURNS UUID AS $$
DECLARE
    v_rider_id UUID;
BEGIN
    INSERT INTO public.riders (
        rider_code, 
        name, 
        emirates_id_number, 
        phone, 
        passport_number, 
        city, 
        status, 
        created_by_user_id
    ) VALUES (
        p_rider_code, 
        p_name, 
        p_emirates_id_number, 
        p_phone, 
        p_passport_number, 
        p_city, 
        'active', 
        p_created_by_user_id
    ) RETURNING id INTO v_rider_id;

    INSERT INTO public.action_items (
        type, 
        title, 
        subtitle, 
        severity, 
        responsible_role, 
        route, 
        reference_id
    ) VALUES (
        'rider_pending_approval', 
        p_name, 
        'New rider pending accountant review', 
        p_action_severity::action_severity, 
        'accountant', 
        '/accountant-dashboard/rider-completion', 
        v_rider_id
    );

    RETURN v_rider_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===== rpc_approve_rider.sql =====
CREATE OR REPLACE FUNCTION rpc_approve_rider(
    p_rider_id UUID,
    p_action_item_id UUID,
    p_wps_status TEXT,
    p_release_hold TEXT,
    p_aliases JSONB
)
RETURNS VOID AS $$
DECLARE
    v_alias RECORD;
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();

    UPDATE public.riders
    SET 
        wps_status = p_wps_status,
        release_hold = p_release_hold,
        status = 'active'
    WHERE id = p_rider_id;

    FOR v_alias IN SELECT * FROM jsonb_to_recordset(p_aliases) 
        AS x(platform TEXT, platform_rider_id TEXT, c3_id TEXT, valid_from DATE)
    LOOP
        UPDATE public.rider_aliases
        SET status = 'inactive', valid_to = v_alias.valid_from - INTERVAL '1 day'
        WHERE rider_id = p_rider_id 
          AND platform = v_alias.platform 
          AND status = 'active';

        INSERT INTO public.rider_aliases (
            rider_id, 
            platform, 
            platform_rider_id, 
            c3_id, 
            valid_from, 
            status
        ) VALUES (
            p_rider_id,
            v_alias.platform,
            v_alias.platform_rider_id,
            v_alias.c3_id,
            v_alias.valid_from,
            'active'
        );
    END LOOP;

    UPDATE public.action_items
    SET
        resolved_at = NOW(),
        resolved_by = v_user_id,
        resolution_notes = 'Rider reviewed and approved by accountant'
    WHERE id = p_action_item_id;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===== scripts/alias_resolution_rpc.sql =====
CREATE OR REPLACE FUNCTION public.fn_resolve_alias_manually(
  p_action_item_id   UUID,
  p_payslip_id        UUID,
  p_rider_id          UUID,
  p_platform          TEXT,
  p_platform_rider_id TEXT,
  p_valid_from        DATE,
  p_resolved_by       UUID
) RETURNS VOID AS $$
DECLARE
  v_batch_id UUID;
  v_rider_name TEXT;
  v_alias_id UUID;
BEGIN
    SELECT name INTO v_rider_name FROM public.riders WHERE id = p_rider_id;
    SELECT batch_id INTO v_batch_id FROM public.payslips WHERE id = p_payslip_id;

    INSERT INTO public.rider_aliases (
        rider_id, 
        platform, 
        platform_rider_id, 
        valid_from, 
        valid_to, 
        status
    ) VALUES (
        p_rider_id, 
        p_platform, 
        p_platform_rider_id, 
        p_valid_from, 
        NULL, 
        'active'
    )
    RETURNING id INTO v_alias_id;

    UPDATE public.payslips
    SET 
        rider_id = p_rider_id,
        rider_alias_id = v_alias_id,
        rider_name = v_rider_name,
        status = 'matched',
      error_reason = NULL,
      review_required = false,
      issue_codes = '[]'::JSONB,
      issue_snapshot = '{}'::JSONB
    WHERE id = p_payslip_id;

    UPDATE public.action_items
    SET 
        resolved_by = p_resolved_by,
        resolved_at = NOW(),
        resolution_notes = 'Manually linked by accountant.'
    WHERE id = p_action_item_id;

    IF NOT EXISTS (
        SELECT 1 
        FROM public.action_items 
        WHERE reference_id IN (SELECT id FROM public.payslips WHERE batch_id = v_batch_id)
          AND type = 'alias_mismatch'
          AND resolved_at IS NULL
    ) THEN
        UPDATE public.payroll_batches
        SET status = 'draft'
        WHERE id = v_batch_id AND status = 'error';
    END IF;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===== rider_onboarding_overhaul.sql: schema & RPCs merged (RLS moved to 2_rls.sql) =====
CREATE TABLE IF NOT EXISTS public.rider_requests (
  id                  UUID         NOT NULL DEFAULT gen_random_uuid(),
  name                TEXT         NOT NULL,
  emirates_id_number  TEXT         NOT NULL,
  phone               TEXT,
  passport_number     TEXT,
  city                TEXT,
  rider_code          TEXT,
  submitted_by        UUID         NOT NULL REFERENCES public.profiles(id),
  status              TEXT         NOT NULL DEFAULT 'pending',
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),

  CONSTRAINT rider_requests_pkey PRIMARY KEY (id),
  CONSTRAINT chk_rider_request_status CHECK (status IN ('pending', 'approved', 'rejected'))
);

CREATE OR REPLACE FUNCTION rpc_submit_rider_request(
    p_rider_code TEXT,
    p_name TEXT,
    p_emirates_id_number TEXT,
    p_phone TEXT,
    p_passport_number TEXT,
    p_city TEXT
)
RETURNS UUID AS $$
DECLARE
    v_request_id UUID;
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();

    INSERT INTO public.rider_requests (
        rider_code, name, emirates_id_number, phone, passport_number, city, submitted_by, status
    ) VALUES (
        p_rider_code, p_name, p_emirates_id_number, p_phone, p_passport_number, p_city, v_user_id, 'pending'
    ) RETURNING id INTO v_request_id;

    INSERT INTO public.action_items (
        type, title, subtitle, severity, responsible_role, route, reference_id
    ) VALUES (
        'rider_pending_approval', 
        p_name, 
        'New rider pending review', 
        'warning', 
        'accountant', 
        '/accountant-dashboard/rider-approval', 
        v_request_id
    );

    RETURN v_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION rpc_approve_rider_request(
    p_request_id UUID,
    p_action_item_id UUID,
    p_name TEXT,
    p_emirates_id_number TEXT,
    p_phone TEXT,
    p_passport_number TEXT,
    p_city TEXT,
    p_rider_code TEXT,
    p_wps_status TEXT,
    p_release_hold TEXT,
    p_aliases JSONB
)
RETURNS VOID AS $$
DECLARE
    v_rider_id UUID;
    v_submitted_by UUID;
    v_user_id UUID;
    v_alias RECORD;
BEGIN
    v_user_id := auth.uid();

    SELECT submitted_by INTO v_submitted_by FROM public.rider_requests WHERE id = p_request_id;

    INSERT INTO public.riders (
        name, emirates_id_number, phone, passport_number, city, rider_code, status, wps_status, release_hold, created_by_user_id
    ) VALUES (
        p_name, p_emirates_id_number, p_phone, p_passport_number, p_city, p_rider_code, 'active', p_wps_status, p_release_hold, v_submitted_by
    ) RETURNING id INTO v_rider_id;

    FOR v_alias IN SELECT * FROM jsonb_to_recordset(p_aliases) 
        AS x(platform TEXT, platform_rider_id TEXT, c3_id TEXT, valid_from DATE)
    LOOP
        INSERT INTO public.rider_aliases (
            rider_id, platform, platform_rider_id, c3_id, valid_from, status
        ) VALUES (
            v_rider_id, v_alias.platform, v_alias.platform_rider_id, v_alias.c3_id, v_alias.valid_from, 'active'
        );
    END LOOP;

    UPDATE public.rider_requests SET status = 'approved' WHERE id = p_request_id;

    UPDATE public.action_items
    SET
        resolved_at = NOW(),
        resolved_by = v_user_id,
        resolution_notes = 'Rider approved by accountant'
    WHERE id = p_action_item_id;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION rpc_reject_rider_request(
    p_request_id UUID,
    p_action_item_id UUID,
    p_rejection_reason TEXT
)
RETURNS VOID AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();

    UPDATE public.rider_requests SET status = 'rejected' WHERE id = p_request_id;

    UPDATE public.action_items
    SET
        resolved_at = NOW(),
        resolved_by = v_user_id,
        resolution_notes = p_rejection_reason
    WHERE id = p_action_item_id;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ===== MERGED FROM: backend\allow_posted_settlement_field_updates.sql =====

-- Allow safe settlement-field updates on posted journals.
-- This keeps journal immutability intact while enabling pay-later settlement recompute.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_block_posted_journal_changes()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Restrict changes on posted/reversed journals.
  IF OLD.status IN ('posted', 'reversed') THEN

    -- 1) Block deletions always.
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'Posted/reversed journals cannot be deleted. Create a reversal journal instead.';
    END IF;

    -- 2) Allow accounting reversal transition only.
    IF NEW.status = 'reversed' AND OLD.status = 'posted' THEN
      RETURN NEW;
    END IF;

    -- 3) Allow settlement aggregate updates on already-posted journals only.
    --    Required for vendor pay-later settlement workflows.
    IF OLD.status = 'posted'
       AND NEW.status = 'posted'
       AND NEW.id = OLD.id
       -- Immutable identity/context fields must stay unchanged.
       AND NEW.entry_date IS NOT DISTINCT FROM OLD.entry_date
       AND NEW.description IS NOT DISTINCT FROM OLD.description
       AND NEW.total_amount IS NOT DISTINCT FROM OLD.total_amount
       AND NEW.base_amount IS NOT DISTINCT FROM OLD.base_amount
       AND NEW.vat_rate IS NOT DISTINCT FROM OLD.vat_rate
       AND NEW.vat_amount IS NOT DISTINCT FROM OLD.vat_amount
       AND NEW.type IS NOT DISTINCT FROM OLD.type
       AND NEW.created_by_user_id IS NOT DISTINCT FROM OLD.created_by_user_id
       AND NEW.created_by_role IS NOT DISTINCT FROM OLD.created_by_role
       AND NEW.approved_by IS NOT DISTINCT FROM OLD.approved_by
       AND NEW.approved_at IS NOT DISTINCT FROM OLD.approved_at
       AND NEW.payment_method IS NOT DISTINCT FROM OLD.payment_method
       AND NEW.drawer_id IS NOT DISTINCT FROM OLD.drawer_id
       AND NEW.is_receivable IS NOT DISTINCT FROM OLD.is_receivable
       AND NEW.is_payable IS NOT DISTINCT FROM OLD.is_payable
       AND NEW.receivable_entity_type IS NOT DISTINCT FROM OLD.receivable_entity_type
       AND NEW.receivable_entity_id IS NOT DISTINCT FROM OLD.receivable_entity_id
       AND NEW.receivable_amount IS NOT DISTINCT FROM OLD.receivable_amount
       AND NEW.reversal_of_journal_id IS NOT DISTINCT FROM OLD.reversal_of_journal_id
       AND NEW.receipt_url IS NOT DISTINCT FROM OLD.receipt_url
       AND NEW.rider_id IS NOT DISTINCT FROM OLD.rider_id
       AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at
       AND NEW.payment_timing IS NOT DISTINCT FROM OLD.payment_timing
       AND NEW.linked_journal_id IS NOT DISTINCT FROM OLD.linked_journal_id
       AND NEW.transaction_number IS NOT DISTINCT FROM OLD.transaction_number
       AND NEW.party_type IS NOT DISTINCT FROM OLD.party_type
       AND NEW.party_id IS NOT DISTINCT FROM OLD.party_id
       AND NEW.source_document_ref IS NOT DISTINCT FROM OLD.source_document_ref
       AND NEW.posted_by IS NOT DISTINCT FROM OLD.posted_by
       AND NEW.narration IS NOT DISTINCT FROM OLD.narration
       AND NEW.remarks IS NOT DISTINCT FROM OLD.remarks
       AND NEW.action_timestamp IS NOT DISTINCT FROM OLD.action_timestamp
       AND NEW.reversal_of_entry_id IS NOT DISTINCT FROM OLD.reversal_of_entry_id
    THEN
      -- Only settlement columns are allowed to change in this branch:
      -- original_payable_amount, settled_amount, outstanding_amount, settlement_status.
      RETURN NEW;
    END IF;

    -- 4) Block all other posted/reversed edits.
    RAISE EXCEPTION 'Posted journals cannot be edited. Status was %. Only Reversal is allowed.', OLD.status;
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;


-- ===== MERGED FROM: backend\backfill_journal_party_and_settlement_fields.sql =====

-- Backfill journal metadata for legacy rows created before backend normalization.
-- Safe to run multiple times.

BEGIN;

-- 1) Normalize party linkage from legacy receivable fields when party fields are missing.
UPDATE journals
SET
  party_type = COALESCE(party_type, receivable_entity_type),
  party_id = COALESCE(party_id, receivable_entity_id)
WHERE party_type IS NULL
  AND receivable_entity_type IN ('vendor', 'supplier', 'rider')
  AND receivable_entity_id IS NOT NULL;

-- 2) Backfill payment_timing for payable rows if missing.
-- If drawer_id is null, this is typically pay_later accrual.
UPDATE journals
SET payment_timing = 'pay_later'
WHERE is_payable = TRUE
  AND status = 'posted'
  AND (payment_timing IS NULL OR BTRIM(payment_timing) = '')
  AND drawer_id IS NULL;

-- If drawer_id is present and payment_timing is still missing, default to pay_now.
UPDATE journals
SET payment_timing = 'pay_now'
WHERE is_payable = TRUE
  AND status = 'posted'
  AND (payment_timing IS NULL OR BTRIM(payment_timing) = '')
  AND drawer_id IS NOT NULL;

-- 3) Ensure original payable amount exists for posted payable rows.
UPDATE journals
SET original_payable_amount = COALESCE(original_payable_amount, total_amount, 0)
WHERE is_payable = TRUE
  AND status = 'posted';

-- 4) Recompute payable settlement aggregates from journal_settlements.
WITH settlement_totals AS (
  SELECT
    source_journal_id,
    SUM(COALESCE(amount, 0))::numeric AS settled_total
  FROM journal_settlements
  GROUP BY source_journal_id
)
UPDATE journals j
SET
  settled_amount = COALESCE(st.settled_total, 0),
  outstanding_amount = GREATEST(
    COALESCE(j.original_payable_amount, j.total_amount, 0) - COALESCE(st.settled_total, 0),
    0
  ),
  settlement_status = CASE
    WHEN GREATEST(
      COALESCE(j.original_payable_amount, j.total_amount, 0) - COALESCE(st.settled_total, 0),
      0
    ) = 0
    AND COALESCE(j.original_payable_amount, j.total_amount, 0) > 0 THEN 'settled'
    WHEN COALESCE(st.settled_total, 0) > 0 THEN 'partially_settled'
    WHEN COALESCE(j.original_payable_amount, j.total_amount, 0) > 0 THEN 'open'
    ELSE 'na'
  END
FROM settlement_totals st
WHERE j.id = st.source_journal_id
  AND j.is_payable = TRUE
  AND j.status = 'posted';

-- 5) Also update posted payable rows with no settlements at all.
UPDATE journals j
SET
  settled_amount = COALESCE(j.settled_amount, 0),
  outstanding_amount = GREATEST(COALESCE(j.original_payable_amount, j.total_amount, 0), 0),
  settlement_status = CASE
    WHEN COALESCE(j.original_payable_amount, j.total_amount, 0) > 0 THEN 'open'
    ELSE 'na'
  END
WHERE j.is_payable = TRUE
  AND j.status = 'posted'
  AND NOT EXISTS (
    SELECT 1
    FROM journal_settlements st
    WHERE st.source_journal_id = j.id
  );

COMMIT;


-- ===== MERGED FROM: backend\create_payroll_skips.sql =====

-- Create the payroll_skips table for silent tracking of cross-platform riders
CREATE TABLE IF NOT EXISTS public.payroll_skips (
  id                UUID         NOT NULL DEFAULT gen_random_uuid(),
  batch_id          UUID         NOT NULL,
  external_id       TEXT         NOT NULL,
  rider_id          UUID,               -- Nullable if name-only or ID-only mismatch
  rider_name        TEXT,
  sheet_platform    TEXT         NOT NULL,
  db_platform       TEXT         NOT NULL,
  reason            TEXT         NOT NULL,
  skipped_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),

  CONSTRAINT payroll_skips_pkey PRIMARY KEY (id),
  CONSTRAINT fk_skips_batch FOREIGN KEY (batch_id) REFERENCES public.payroll_batches (id) ON DELETE CASCADE,
  CONSTRAINT fk_skips_rider FOREIGN KEY (rider_id) REFERENCES public.riders (id) ON DELETE SET NULL
);

-- Index for traceability
CREATE INDEX IF NOT EXISTS idx_payroll_skips_batch ON public.payroll_skips(batch_id);


-- ===== MERGED FROM: backend\supabase_drop_payslip_internal_columns.sql =====

-- ============================================================
-- Supabase Migration: Remove legacy internal payslip columns
-- Project: rider_payroll_erp
-- Purpose:
--   1) Preserve totals data before column removal
--   2) Drop deprecated columns: internal_fines, internal_expenses
-- Notes:
--   - Idempotent and safe to run repeatedly
-- ============================================================

BEGIN;

-- Backfill totals only when legacy values exist and totals are missing/zero.
UPDATE public.payslips
SET
  total_fines = CASE
    WHEN COALESCE(total_fines, 0) = 0 AND COALESCE(internal_fines, 0) > 0
      THEN COALESCE(internal_fines, 0)
    ELSE COALESCE(total_fines, 0)
  END,
  total_expenses = CASE
    WHEN COALESCE(total_expenses, 0) = 0 AND COALESCE(internal_expenses, 0) > 0
      THEN COALESCE(internal_expenses, 0)
    ELSE COALESCE(total_expenses, 0)
  END
WHERE
  COALESCE(internal_fines, 0) > 0
  OR COALESCE(internal_expenses, 0) > 0;

ALTER TABLE IF EXISTS public.payslips
  DROP COLUMN IF EXISTS internal_fines,
  DROP COLUMN IF EXISTS internal_expenses;

COMMIT;


-- ===== MERGED FROM: backend\supabase_payslip_review_flags_migration.sql =====

-- ============================================================
-- Supabase Migration: Payslip Review Flags (Non-Breaking)
-- Project: rider_payroll_erp
-- Purpose:
--   1) Add review metadata columns to payslips
--   2) Add FK for adjusted_by -> profiles(id)
--   3) Add index for fast filtering of flagged payslips
-- Notes:
--   - Additive changes only; existing logic remains valid
--   - Safe for repeated execution (idempotent)
-- ============================================================

BEGIN;

ALTER TABLE IF EXISTS public.payslips
  ADD COLUMN IF NOT EXISTS review_required BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS issue_codes JSONB NOT NULL DEFAULT '[]'::JSONB,
  ADD COLUMN IF NOT EXISTS issue_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  ADD COLUMN IF NOT EXISTS adjusted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS adjusted_by UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_payslips_adjusted_by'
  ) THEN
    ALTER TABLE public.payslips
      ADD CONSTRAINT fk_payslips_adjusted_by
      FOREIGN KEY (adjusted_by)
      REFERENCES public.profiles(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_payslips_review_required
  ON public.payslips (review_required)
  WHERE review_required = true;

-- Upload/finalization performance indexes
CREATE INDEX IF NOT EXISTS idx_payslips_batch_id
  ON public.payslips (batch_id);

CREATE INDEX IF NOT EXISTS idx_payslips_rider_id
  ON public.payslips (rider_id);

CREATE INDEX IF NOT EXISTS idx_traffic_fines_rider_status
  ON public.traffic_fines (rider_id, status);

CREATE INDEX IF NOT EXISTS idx_expenses_rider_status
  ON public.expenses (rider_id, status);

CREATE INDEX IF NOT EXISTS idx_rider_aliases_platform_id_status
  ON public.rider_aliases (platform, platform_rider_id, status);

COMMIT;


-- ===== MERGED FROM: backend\vendor_pay_later_and_settlement_migration.sql =====

-- Vendor pay-later and settlement migration
-- Additive migration for deferred payment and vendor credit application.

BEGIN;

-- 1) Extend journals with deferred payment and settlement tracking.
ALTER TABLE public.journals
  ADD COLUMN IF NOT EXISTS payment_timing TEXT NOT NULL DEFAULT 'pay_now',
  ADD COLUMN IF NOT EXISTS linked_journal_id UUID,
  ADD COLUMN IF NOT EXISTS original_payable_amount NUMERIC NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS settled_amount NUMERIC NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS outstanding_amount NUMERIC NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS settlement_status TEXT NOT NULL DEFAULT 'na';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name = 'journals'
      AND constraint_name = 'fk_journals_linked_journal'
  ) THEN
    ALTER TABLE public.journals
      ADD CONSTRAINT fk_journals_linked_journal
      FOREIGN KEY (linked_journal_id) REFERENCES public.journals(id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name = 'journals'
      AND constraint_name = 'chk_journals_payment_timing'
  ) THEN
    ALTER TABLE public.journals
      ADD CONSTRAINT chk_journals_payment_timing
      CHECK (payment_timing IN ('pay_now', 'pay_later'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name = 'journals'
      AND constraint_name = 'chk_journals_settlement_status'
  ) THEN
    ALTER TABLE public.journals
      ADD CONSTRAINT chk_journals_settlement_status
      CHECK (settlement_status IN ('na', 'open', 'partially_settled', 'settled'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_journals_linked_journal_id ON public.journals (linked_journal_id);
CREATE INDEX IF NOT EXISTS idx_journals_settlement_status ON public.journals (settlement_status);

-- 2) Replace posted-journal drawer check to support pay-later payable journals.
ALTER TABLE public.journals DROP CONSTRAINT IF EXISTS chk_posted_journal_has_drawer;
ALTER TABLE public.journals
  ADD CONSTRAINT chk_posted_journal_has_drawer
  CHECK (
    status != 'posted'
    OR (drawer_id IS NOT NULL AND payment_method IS NOT NULL)
    OR (is_payable = true AND payment_timing = 'pay_later')
    OR (type = 'salary' AND (description ILIKE '%accrual%' OR description ILIKE '%deduction%'))
  );

-- 3) Settlement table: credit applications and payment settlements.
CREATE TABLE IF NOT EXISTS public.journal_settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_journal_id UUID NOT NULL REFERENCES public.journals(id),
  target_journal_id UUID NOT NULL REFERENCES public.journals(id),
  settlement_type TEXT NOT NULL,
  amount NUMERIC NOT NULL CHECK (amount > 0),
  note TEXT,
  created_by_user_id UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_journal_settlements_type CHECK (settlement_type IN ('credit_apply', 'payment'))
);

CREATE INDEX IF NOT EXISTS idx_journal_settlements_source ON public.journal_settlements (source_journal_id);
CREATE INDEX IF NOT EXISTS idx_journal_settlements_target ON public.journal_settlements (target_journal_id);

-- 4) Function to get open vendor receivable credits.
CREATE OR REPLACE FUNCTION public.fn_get_vendor_open_credits(p_vendor_id UUID)
RETURNS TABLE (
  journal_id UUID,
  entry_date DATE,
  description TEXT,
  total_receivable NUMERIC,
  applied_amount NUMERIC,
  open_amount NUMERIC
)
LANGUAGE SQL
STABLE
AS $$
  SELECT
    j.id AS journal_id,
    j.entry_date,
    j.description,
    COALESCE(j.receivable_amount, 0) AS total_receivable,
    COALESCE((
      SELECT SUM(js.amount)
      FROM public.journal_settlements js
      WHERE js.source_journal_id = j.id
        AND js.settlement_type = 'credit_apply'
    ), 0) AS applied_amount,
    COALESCE(j.receivable_amount, 0) - COALESCE((
      SELECT SUM(js.amount)
      FROM public.journal_settlements js
      WHERE js.source_journal_id = j.id
        AND js.settlement_type = 'credit_apply'
    ), 0) AS open_amount
  FROM public.journals j
  WHERE j.status = 'posted'
    AND j.is_receivable = true
    AND lower(COALESCE(j.party_type, j.receivable_entity_type)) = 'vendor'
    AND COALESCE(j.party_id, j.receivable_entity_id) = p_vendor_id
    AND COALESCE(j.receivable_amount, 0) > 0
    AND (
      COALESCE(j.receivable_amount, 0) - COALESCE((
        SELECT SUM(js.amount)
        FROM public.journal_settlements js
        WHERE js.source_journal_id = j.id
          AND js.settlement_type = 'credit_apply'
      ), 0)
    ) > 0
  ORDER BY j.entry_date, j.created_at;
$$;

COMMIT;


-- ===== MERGED FROM: backend\fix_vat_duplicate_ledger_rows.sql =====

-- Fix duplicate/wrong VAT ledger rows for expense journals.
-- Problem addressed:
-- - Existing trigger logic remapped ALL debit lines to base_amount for expense journals.
-- - When a vat_payable journal line already exists, this creates a wrong extra VAT debit (e.g., 1800 instead of 90).
--
-- New logic:
-- 1) Insert journal_lines into ledger as-is.
-- 2) Only add auto VAT ledger row for legacy expense journals that have VAT amount > 0
--    AND do NOT already contain a vat_payable journal line.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_post_journal_to_ledger()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_expense_id         UUID;
  v_expense_vat_amount NUMERIC;
  v_rider_id           UUID;
  v_has_vat_line       BOOLEAN := FALSE;
BEGIN
  IF NEW.status = 'posted' AND OLD.status = 'draft' THEN

    SELECT id, vat_amount
    INTO v_expense_id, v_expense_vat_amount
    FROM public.expenses
    WHERE journal_id = NEW.id
    LIMIT 1;

    IF v_expense_id IS NOT NULL THEN
      SELECT rider_id INTO v_rider_id
      FROM public.expenses
      WHERE id = v_expense_id
      LIMIT 1;
    ELSIF NEW.receivable_entity_type = 'rider' AND NEW.receivable_entity_id IS NOT NULL THEN
      v_rider_id := NEW.receivable_entity_id;
    END IF;

    -- Always post explicit journal lines exactly as entered.
    INSERT INTO public.ledger (
      journal_id, journal_line_id, account_id,
      debit_amount, credit_amount, rider_id
    )
    SELECT
      jl.journal_id,
      jl.id,
      jl.account_id,
      jl.debit_amount,
      jl.credit_amount,
      v_rider_id
    FROM public.journal_lines jl
    WHERE jl.journal_id = NEW.id;

    -- Auto-add VAT row only for legacy expense journals that do not include vat_payable line.
    IF v_expense_id IS NOT NULL AND COALESCE(v_expense_vat_amount, 0) > 0 THEN
      SELECT EXISTS (
        SELECT 1
        FROM public.journal_lines jl
        WHERE jl.journal_id = NEW.id
          AND lower(COALESCE(jl.account_id, '')) = 'vat_payable'
      ) INTO v_has_vat_line;

      IF NOT v_has_vat_line THEN
        INSERT INTO public.ledger (
          journal_id, journal_line_id, account_id,
          debit_amount, credit_amount, rider_id
        )
        SELECT
          NEW.id,
          jl.id,
          'vat_payable',
          v_expense_vat_amount,
          0,
          v_rider_id
        FROM public.journal_lines jl
        WHERE jl.journal_id = NEW.id
          AND jl.debit_amount > 0
        LIMIT 1;
      END IF;
    END IF;

  END IF;

  RETURN NEW;
END;
$$;

COMMIT;


-- ===== MERGED FROM: scripts\rpc_reverse_journal.sql =====

-- ============================================================
-- RPC: rpc_reverse_journal
-- Handles atomic reversal of journals, including:
--  1. Identifying all related journals (payroll links, etc.)
--  2. Restoring drawer balances
--  3. Unlinking and resetting expenses to 'pending'
--  4. Deleting related ledger rows (bypassing RLS via SECURITY DEFINER)
--  5. Updating journal status to 'reversed'
--  6. Unlocking payslips to 'matched'
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_reverse_journal(
    p_journal_id UUID,
    p_reason TEXT
)
RETURNS VOID AS $$
DECLARE
    v_journal_ids UUID[];
    v_receipt_url TEXT;
    v_description TEXT;
    v_payslip_id UUID;
    v_journal RECORD;
    v_shared_uuid TEXT;
BEGIN
    -- 1. Fetch root journal info
    SELECT receipt_url, description INTO v_receipt_url, v_description
    FROM public.journals WHERE id = p_journal_id;

    -- 2. Identify all journals to reverse
    IF v_receipt_url LIKE 'payroll_link:%' THEN
        -- Case A: Payroll link exists
        v_payslip_id := (REPLACE(v_receipt_url, 'payroll_link:', ''))::UUID;
        SELECT array_agg(id) INTO v_journal_ids
        FROM public.journals 
        WHERE receipt_url = v_receipt_url AND status != 'reversed';
    ELSE
        -- Case B: Check for shared UUID in brackets [Post: UUID]
        v_shared_uuid := substring(v_description from '\[Post: ([a-f0-9\-]+)\]');
        
        IF v_shared_uuid IS NOT NULL THEN
            SELECT array_agg(id) INTO v_journal_ids
            FROM public.journals
            WHERE description LIKE '%' || v_shared_uuid || '%' AND status != 'reversed';
        ELSE
            -- Case C: Single standalone journal
            v_journal_ids := ARRAY[p_journal_id];
        END IF;

        -- Try to find a linked payslip if not already found
        SELECT id INTO v_payslip_id 
        FROM public.payslips 
        WHERE journal_id = ANY(v_journal_ids) OR id = v_payslip_id
        LIMIT 1;
    END IF;

    -- 3. Loop through identified journals for financial cleanup
    FOR v_journal IN 
        SELECT id, drawer_id, total_amount 
        FROM public.journals 
        WHERE id = ANY(v_journal_ids)
    LOOP
        -- A. RESTORE DRAWER BALANCE
        IF v_journal.drawer_id IS NOT NULL AND v_journal.total_amount != 0 THEN
            UPDATE public.drawer 
            SET balance = balance + v_journal.total_amount 
            WHERE id = v_journal.drawer_id;
        END IF;

        -- B. RECOVER LINKED EXPENSES (Unlink and reset to pending)
        UPDATE public.expenses 
        SET journal_id = NULL, status = 'pending' 
        WHERE journal_id = v_journal.id;
    END LOOP;

    -- 4. DELETE LEDGER ENTRIES (Cleanup Trial Balance / Statements)
    -- This works because the function is SECURITY DEFINER
    DELETE FROM public.ledger WHERE journal_id = ANY(v_journal_ids);

    -- 5. MARK JOURNALS AS REVERSED
    UPDATE public.journals 
    SET status = 'reversed' 
    WHERE id = ANY(v_journal_ids);

    -- 6. RESET PAYSLIP STATUS (If linked)
    IF v_payslip_id IS NOT NULL THEN
        UPDATE public.payslips 
        SET status = 'matched', journal_id = NULL 
        WHERE id = v_payslip_id;
    END IF;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ===== MERGED (SCHEMA) FROM: backend\vendor_supplier_accounting_workflow_migration.sql =====

-- Vendor and Supplier Accounting Workflow Migration
-- Source: Vendor_Supplier_Accounting_Workflow.pdf
-- Safe, additive migration designed to avoid breaking existing integrations.

BEGIN;

-- ============================================================
-- 1) Master tables: vendors and suppliers
-- ============================================================
CREATE TABLE IF NOT EXISTS public.vendors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_code TEXT NOT NULL UNIQUE DEFAULT ('VND-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  address TEXT,
  vat_applicable BOOLEAN NOT NULL DEFAULT true,
  vat_no TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by_user_id UUID REFERENCES public.profiles(id)
);

CREATE INDEX IF NOT EXISTS idx_vendors_name ON public.vendors (name);
CREATE INDEX IF NOT EXISTS idx_vendors_status ON public.vendors (status);

CREATE TABLE IF NOT EXISTS public.suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_code TEXT NOT NULL UNIQUE DEFAULT ('SUP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  address TEXT,
  vat_applicable BOOLEAN NOT NULL DEFAULT false,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by_user_id UUID REFERENCES public.profiles(id)
);

CREATE INDEX IF NOT EXISTS idx_suppliers_name ON public.suppliers (name);
CREATE INDEX IF NOT EXISTS idx_suppliers_status ON public.suppliers (status);

-- ============================================================
-- 2) Audit + party-linking columns on journals
-- ============================================================
ALTER TABLE public.journals
  ADD COLUMN IF NOT EXISTS transaction_number TEXT,
  ADD COLUMN IF NOT EXISTS party_type TEXT,
  ADD COLUMN IF NOT EXISTS party_id UUID,
  ADD COLUMN IF NOT EXISTS source_document_ref TEXT,
  ADD COLUMN IF NOT EXISTS posted_by UUID,
  ADD COLUMN IF NOT EXISTS narration TEXT,
  ADD COLUMN IF NOT EXISTS remarks TEXT,
  ADD COLUMN IF NOT EXISTS action_timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS reversal_of_entry_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name = 'journals'
      AND constraint_name = 'fk_journals_posted_by'
  ) THEN
    ALTER TABLE public.journals
      ADD CONSTRAINT fk_journals_posted_by
      FOREIGN KEY (posted_by) REFERENCES public.profiles(id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name = 'journals'
      AND constraint_name = 'fk_journals_reversal_of_entry'
  ) THEN
    ALTER TABLE public.journals
      ADD CONSTRAINT fk_journals_reversal_of_entry
      FOREIGN KEY (reversal_of_entry_id) REFERENCES public.journals(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_journals_party_type_party_id ON public.journals (party_type, party_id);
CREATE INDEX IF NOT EXISTS idx_journals_transaction_number ON public.journals (transaction_number);

-- Keep legacy and new fields synchronized for backward compatibility.
CREATE OR REPLACE FUNCTION public.fn_sync_journal_party_fields()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.party_type IS NULL AND NEW.receivable_entity_type IS NOT NULL THEN
    NEW.party_type := lower(NEW.receivable_entity_type);
  END IF;

  IF NEW.party_id IS NULL AND NEW.receivable_entity_id IS NOT NULL THEN
    NEW.party_id := NEW.receivable_entity_id;
  END IF;

  IF NEW.receivable_entity_type IS NULL AND NEW.party_type IS NOT NULL THEN
    NEW.receivable_entity_type := lower(NEW.party_type);
  END IF;

  IF NEW.receivable_entity_id IS NULL AND NEW.party_id IS NOT NULL THEN
    NEW.receivable_entity_id := NEW.party_id;
  END IF;

  IF NEW.reversal_of_entry_id IS NULL AND NEW.reversal_of_journal_id IS NOT NULL THEN
    NEW.reversal_of_entry_id := NEW.reversal_of_journal_id;
  END IF;

  IF NEW.reversal_of_journal_id IS NULL AND NEW.reversal_of_entry_id IS NOT NULL THEN
    NEW.reversal_of_journal_id := NEW.reversal_of_entry_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_journal_party_fields ON public.journals;
CREATE TRIGGER trg_sync_journal_party_fields
  BEFORE INSERT OR UPDATE ON public.journals
  FOR EACH ROW EXECUTE FUNCTION public.fn_sync_journal_party_fields();

-- Backfill existing rows once.
UPDATE public.journals
SET
  party_type = COALESCE(party_type, lower(receivable_entity_type)),
  party_id = COALESCE(party_id, receivable_entity_id),
  reversal_of_entry_id = COALESCE(reversal_of_entry_id, reversal_of_journal_id)
WHERE
  party_type IS NULL
  OR party_id IS NULL
  OR reversal_of_entry_id IS NULL;

-- Populate transaction numbers where missing.
UPDATE public.journals
SET transaction_number = 'JRN-' || to_char(COALESCE(created_at, now()), 'YYYYMMDD') || '-' || lpad(substr(replace(id::text, '-', ''), 1, 6), 6, '0')
WHERE transaction_number IS NULL;

-- ============================================================
-- 3) Party-linking columns on journal_lines and ledger
-- ============================================================
ALTER TABLE public.journal_lines
  ADD COLUMN IF NOT EXISTS party_type TEXT,
  ADD COLUMN IF NOT EXISTS party_id UUID;

CREATE INDEX IF NOT EXISTS idx_journal_lines_party_type_party_id ON public.journal_lines (party_type, party_id);

CREATE OR REPLACE FUNCTION public.fn_fill_journal_line_party_fields()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_party_type TEXT;
  v_party_id UUID;
BEGIN
  SELECT party_type, party_id
  INTO v_party_type, v_party_id
  FROM public.journals
  WHERE id = NEW.journal_id;

  IF NEW.party_type IS NULL THEN
    NEW.party_type := v_party_type;
  END IF;

  IF NEW.party_id IS NULL THEN
    NEW.party_id := v_party_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fill_journal_line_party_fields ON public.journal_lines;
CREATE TRIGGER trg_fill_journal_line_party_fields
  BEFORE INSERT OR UPDATE ON public.journal_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_fill_journal_line_party_fields();

UPDATE public.journal_lines jl
SET
  party_type = COALESCE(jl.party_type, j.party_type),
  party_id = COALESCE(jl.party_id, j.party_id)
FROM public.journals j
WHERE j.id = jl.journal_id
  AND (jl.party_type IS NULL OR jl.party_id IS NULL);

ALTER TABLE public.ledger
  ADD COLUMN IF NOT EXISTS party_type TEXT,
  ADD COLUMN IF NOT EXISTS party_id UUID,
  ADD COLUMN IF NOT EXISTS source_document_ref TEXT;

CREATE INDEX IF NOT EXISTS idx_ledger_party_type_party_id ON public.ledger (party_type, party_id);

-- ============================================================
-- 4) Data integrity guards for party profile + VAT logic
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_validate_vendor_supplier_journal()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_party_type TEXT := lower(COALESCE(NEW.party_type, NEW.receivable_entity_type, ''));
  v_party_id UUID := COALESCE(NEW.party_id, NEW.receivable_entity_id);
  v_exists BOOLEAN := false;
BEGIN
  IF v_party_type <> '' AND v_party_type NOT IN ('vendor', 'supplier', 'rider') THEN
    RAISE EXCEPTION 'Invalid party_type: %. Allowed values are vendor/supplier/rider.', v_party_type;
  END IF;

  IF v_party_type <> '' AND v_party_id IS NULL THEN
    RAISE EXCEPTION 'party_id is required when party_type is set.';
  END IF;

  IF v_party_type = 'vendor' THEN
    SELECT EXISTS(SELECT 1 FROM public.vendors WHERE id = v_party_id) INTO v_exists;
    IF NOT v_exists THEN
      RAISE EXCEPTION 'Vendor does not exist for party_id: %', v_party_id;
    END IF;
  ELSIF v_party_type = 'supplier' THEN
    SELECT EXISTS(SELECT 1 FROM public.suppliers WHERE id = v_party_id) INTO v_exists;
    IF NOT v_exists THEN
      RAISE EXCEPTION 'Supplier does not exist for party_id: %', v_party_id;
    END IF;

    IF COALESCE(NEW.vat_rate, 0) <> 0 OR COALESCE(NEW.vat_amount, 0) <> 0 THEN
      RAISE EXCEPTION 'Supplier flow does not allow VAT values. vat_rate and vat_amount must be 0.';
    END IF;
  ELSIF v_party_type = 'rider' THEN
    SELECT EXISTS(SELECT 1 FROM public.riders WHERE id = v_party_id) INTO v_exists;
    IF NOT v_exists THEN
      RAISE EXCEPTION 'Rider does not exist for party_id: %', v_party_id;
    END IF;
  END IF;

  NEW.action_timestamp := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_vendor_supplier_journal ON public.journals;
CREATE TRIGGER trg_validate_vendor_supplier_journal
  BEFORE INSERT OR UPDATE ON public.journals
  FOR EACH ROW EXECUTE FUNCTION public.fn_validate_vendor_supplier_journal();

-- ============================================================
-- 5) Replace ledger posting trigger to carry party/source references
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_post_journal_to_ledger()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_expense_id         UUID;
  v_expense_amount     NUMERIC;
  v_expense_vat_amount NUMERIC;
  v_expense_base       NUMERIC;
  v_rider_id           UUID;
  v_party_type         TEXT;
  v_party_id           UUID;
BEGIN
  IF NEW.status = 'posted' AND OLD.status = 'draft' THEN
    v_party_type := lower(COALESCE(NEW.party_type, NEW.receivable_entity_type));
    v_party_id := COALESCE(NEW.party_id, NEW.receivable_entity_id);

    SELECT id, amount, vat_amount, base_amount
    INTO v_expense_id, v_expense_amount, v_expense_vat_amount, v_expense_base
    FROM public.expenses
    WHERE journal_id = NEW.id
    LIMIT 1;

    IF v_expense_id IS NOT NULL THEN
      SELECT rider_id INTO v_rider_id FROM public.expenses WHERE id = v_expense_id LIMIT 1;

      INSERT INTO public.ledger (
        journal_id, journal_line_id, account_id,
        debit_amount, credit_amount, rider_id, party_type, party_id, source_document_ref
      )
      SELECT
        jl.journal_id,
        jl.id,
        jl.account_id,
        CASE WHEN jl.debit_amount > 0
          THEN COALESCE(v_expense_base, v_expense_amount)
          ELSE 0
        END,
        CASE WHEN jl.credit_amount > 0
          THEN COALESCE(v_expense_amount, 0)
          ELSE 0
        END,
        v_rider_id,
        COALESCE(jl.party_type, v_party_type),
        COALESCE(jl.party_id, v_party_id),
        NEW.source_document_ref
      FROM public.journal_lines jl
      WHERE jl.journal_id = NEW.id;

      IF COALESCE(v_expense_vat_amount, 0) > 0 THEN
        INSERT INTO public.ledger (
          journal_id, journal_line_id, account_id,
          debit_amount, credit_amount, rider_id, party_type, party_id, source_document_ref
        )
        SELECT
          NEW.id,
          jl.id,
          'vat_payable',
          v_expense_vat_amount,
          0,
          v_rider_id,
          COALESCE(jl.party_type, v_party_type),
          COALESCE(jl.party_id, v_party_id),
          NEW.source_document_ref
        FROM public.journal_lines jl
        WHERE jl.journal_id = NEW.id
          AND jl.debit_amount > 0
        LIMIT 1;
      END IF;

    ELSE
      IF v_party_type = 'rider' AND v_party_id IS NOT NULL THEN
        v_rider_id := v_party_id;
      END IF;

      INSERT INTO public.ledger (
        journal_id, journal_line_id, account_id,
        debit_amount, credit_amount, rider_id, party_type, party_id, source_document_ref
      )
      SELECT
        jl.journal_id,
        jl.id,
        jl.account_id,
        jl.debit_amount,
        jl.credit_amount,
        v_rider_id,
        COALESCE(jl.party_type, v_party_type),
        COALESCE(jl.party_id, v_party_id),
        NEW.source_document_ref
      FROM public.journal_lines jl
      WHERE jl.journal_id = NEW.id;

    END IF;

  END IF;
  RETURN NEW;
END;
$$;





-- ===== MERGED (SCHEMA) FROM: backend\rider_module_enhancements_migration.sql =====

-- ============================================================
-- RIDER MODULE ENHANCEMENTS MIGRATION
-- Date: 2026-04-02
-- Notes:
--   - Additive and backward-compatible only.
--   - Safe to run multiple times (IF NOT EXISTS / OR REPLACE).
-- ============================================================

BEGIN;

-- ============================================================
-- 1) Rider document expiry management
-- ============================================================
ALTER TABLE public.riders
  ADD COLUMN IF NOT EXISTS passport_expiry_date DATE,
  ADD COLUMN IF NOT EXISTS emirates_id_expiry_date DATE,
  ADD COLUMN IF NOT EXISTS visa_expiry_date DATE;

CREATE TABLE IF NOT EXISTS public.rider_document_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID NOT NULL REFERENCES public.riders(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL CHECK (document_type IN ('passport', 'emirates_id', 'visa')),
  expiry_date DATE NOT NULL,
  days_to_expiry INTEGER NOT NULL,
  alert_level TEXT NOT NULL CHECK (alert_level IN ('expired', 'critical', 'warning', 'upcoming')),
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  resolution_notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_rider_document_alerts_rider_id
  ON public.rider_document_alerts(rider_id);

CREATE INDEX IF NOT EXISTS idx_rider_document_alerts_unresolved
  ON public.rider_document_alerts(alert_level, resolved_at)
  WHERE resolved_at IS NULL;

CREATE OR REPLACE VIEW public.v_rider_document_expiry AS
SELECT
  r.id AS rider_id,
  r.name AS rider_name,
  docs.document_type,
  docs.expiry_date,
  (docs.expiry_date - CURRENT_DATE) AS days_to_expiry,
  CASE
    WHEN docs.expiry_date < CURRENT_DATE THEN 'expired'
    WHEN docs.expiry_date <= CURRENT_DATE + 7 THEN 'critical'
    WHEN docs.expiry_date <= CURRENT_DATE + 30 THEN 'warning'
    ELSE 'upcoming'
  END AS alert_level
FROM public.riders r
CROSS JOIN LATERAL (
  VALUES
    ('passport'::TEXT, r.passport_expiry_date),
    ('emirates_id'::TEXT, r.emirates_id_expiry_date),
    ('visa'::TEXT, r.visa_expiry_date)
) AS docs(document_type, expiry_date)
WHERE docs.expiry_date IS NOT NULL;

-- ============================================================
-- 2) Rider status transition workflow with audit trail
-- ============================================================
CREATE TABLE IF NOT EXISTS public.rider_status_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID NOT NULL REFERENCES public.riders(id) ON DELETE CASCADE,
  old_status rider_status,
  new_status rider_status NOT NULL,
  reason TEXT,
  effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
  expected_return_date DATE,
  changed_by UUID REFERENCES public.profiles(id),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rider_status_history_rider_id_changed_at
  ON public.rider_status_history(rider_id, changed_at DESC);

CREATE OR REPLACE FUNCTION public.fn_log_rider_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.rider_status_history (
      rider_id,
      old_status,
      new_status,
      reason,
      effective_from,
      changed_by,
      changed_at
    ) VALUES (
      NEW.id,
      OLD.status,
      NEW.status,
      COALESCE(current_setting('app.rider_status_reason', true), 'status changed'),
      CURRENT_DATE,
      NULLIF(current_setting('app.current_user_id', true), '')::UUID,
      now()
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_rider_status_change ON public.riders;
CREATE TRIGGER trg_log_rider_status_change
AFTER UPDATE OF status ON public.riders
FOR EACH ROW
EXECUTE FUNCTION public.fn_log_rider_status_change();

CREATE OR REPLACE FUNCTION public.rpc_update_rider_status(
  p_rider_id UUID,
  p_new_status rider_status,
  p_reason TEXT DEFAULT NULL,
  p_effective_from DATE DEFAULT CURRENT_DATE,
  p_expected_return_date DATE DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_old_status rider_status;
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();

  SELECT status INTO v_old_status
  FROM public.riders
  WHERE id = p_rider_id;

  IF v_old_status IS NULL THEN
    RAISE EXCEPTION 'Rider not found: %', p_rider_id;
  END IF;

  UPDATE public.riders
  SET status = p_new_status
  WHERE id = p_rider_id;

  INSERT INTO public.rider_status_history (
    rider_id,
    old_status,
    new_status,
    reason,
    effective_from,
    expected_return_date,
    changed_by,
    changed_at
  ) VALUES (
    p_rider_id,
    v_old_status,
    p_new_status,
    p_reason,
    COALESCE(p_effective_from, CURRENT_DATE),
    p_expected_return_date,
    v_user_id,
    now()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 3) Release/Hold reason tracking
-- ============================================================
ALTER TABLE public.riders
  ADD COLUMN IF NOT EXISTS hold_reason TEXT,
  ADD COLUMN IF NOT EXISTS hold_until DATE,
  ADD COLUMN IF NOT EXISTS hold_set_by UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS hold_set_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.rider_hold_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID NOT NULL REFERENCES public.riders(id) ON DELETE CASCADE,
  old_release_hold TEXT,
  new_release_hold TEXT NOT NULL,
  reason TEXT,
  hold_until DATE,
  changed_by UUID REFERENCES public.profiles(id),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rider_hold_history_rider_id_changed_at
  ON public.rider_hold_history(rider_id, changed_at DESC);

CREATE OR REPLACE FUNCTION public.fn_log_rider_hold_change()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.release_hold IS DISTINCT FROM OLD.release_hold
     OR NEW.hold_reason IS DISTINCT FROM OLD.hold_reason
     OR NEW.hold_until IS DISTINCT FROM OLD.hold_until THEN
    INSERT INTO public.rider_hold_history (
      rider_id,
      old_release_hold,
      new_release_hold,
      reason,
      hold_until,
      changed_by,
      changed_at
    ) VALUES (
      NEW.id,
      OLD.release_hold,
      NEW.release_hold,
      NEW.hold_reason,
      NEW.hold_until,
      NEW.hold_set_by,
      now()
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_rider_hold_change ON public.riders;
CREATE TRIGGER trg_log_rider_hold_change
AFTER UPDATE OF release_hold, hold_reason, hold_until ON public.riders
FOR EACH ROW
EXECUTE FUNCTION public.fn_log_rider_hold_change();

CREATE OR REPLACE FUNCTION public.rpc_set_rider_release_hold(
  p_rider_id UUID,
  p_new_release_hold TEXT,
  p_reason TEXT DEFAULT NULL,
  p_hold_until DATE DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_old_release_hold TEXT;
  v_user_id UUID;
BEGIN
  IF p_new_release_hold NOT IN ('release', 'hold') THEN
    RAISE EXCEPTION 'Invalid release_hold value: %', p_new_release_hold;
  END IF;

  v_user_id := auth.uid();

  SELECT release_hold INTO v_old_release_hold
  FROM public.riders
  WHERE id = p_rider_id;

  IF v_old_release_hold IS NULL THEN
    RAISE EXCEPTION 'Rider not found: %', p_rider_id;
  END IF;

  UPDATE public.riders
  SET
    release_hold = p_new_release_hold,
    hold_reason = CASE WHEN p_new_release_hold = 'hold' THEN p_reason ELSE NULL END,
    hold_until = CASE WHEN p_new_release_hold = 'hold' THEN p_hold_until ELSE NULL END,
    hold_set_by = v_user_id,
    hold_set_at = now()
  WHERE id = p_rider_id;

  INSERT INTO public.rider_hold_history (
    rider_id,
    old_release_hold,
    new_release_hold,
    reason,
    hold_until,
    changed_by,
    changed_at
  ) VALUES (
    p_rider_id,
    v_old_release_hold,
    p_new_release_hold,
    p_reason,
    p_hold_until,
    v_user_id,
    now()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 4) Alias timeline conflict preview helper
-- ============================================================
CREATE OR REPLACE FUNCTION public.rpc_preview_rider_alias_conflicts(
  p_rider_id UUID,
  p_platform TEXT,
  p_platform_rider_id TEXT,
  p_valid_from DATE
)
RETURNS JSONB AS $$
DECLARE
  v_other_rider_conflicts INTEGER := 0;
  v_same_rider_active_conflicts INTEGER := 0;
  v_payload JSONB;
BEGIN
  IF p_platform NOT IN ('talabat', 'keeta') THEN
    RAISE EXCEPTION 'Unsupported platform: %', p_platform;
  END IF;

  SELECT COUNT(*)
    INTO v_other_rider_conflicts
  FROM public.rider_aliases ra
  WHERE ra.platform = p_platform
    AND lower(ra.platform_rider_id) = lower(p_platform_rider_id)
    AND ra.rider_id <> p_rider_id;

  SELECT COUNT(*)
    INTO v_same_rider_active_conflicts
  FROM public.rider_aliases ra
  WHERE ra.platform = p_platform
    AND ra.rider_id = p_rider_id
    AND ra.status = 'active'
    AND ra.valid_to IS NULL
    AND (p_valid_from IS NULL OR ra.valid_from <= p_valid_from);

  v_payload := jsonb_build_object(
    'has_conflict', (v_other_rider_conflicts > 0),
    'other_rider_conflicts', v_other_rider_conflicts,
    'same_rider_active_conflicts', v_same_rider_active_conflicts,
    'platform', p_platform,
    'platform_rider_id', p_platform_rider_id,
    'valid_from', p_valid_from,
    'matches', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'alias_id', ra.id,
            'rider_id', ra.rider_id,
            'platform', ra.platform,
            'platform_rider_id', ra.platform_rider_id,
            'status', ra.status,
            'valid_from', ra.valid_from,
            'valid_to', ra.valid_to
          )
        )
        FROM public.rider_aliases ra
        WHERE ra.platform = p_platform
          AND lower(ra.platform_rider_id) = lower(p_platform_rider_id)
      ),
      '[]'::jsonb
    )
  );

  RETURN v_payload;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5) Rider statement analytics summary helper
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_get_rider_statement_summary(
  p_rider_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_payload JSONB;
BEGIN
  SELECT jsonb_build_object(
    'rider_id', p_rider_id,
    'totals', jsonb_build_object(
      'debit', COALESCE(SUM(l.debit_amount), 0),
      'credit', COALESCE(SUM(l.credit_amount), 0),
      'net_balance', COALESCE(SUM(l.debit_amount - l.credit_amount), 0)
    ),
    'monthly', COALESCE(
      (
        SELECT jsonb_agg(month_row ORDER BY month_row.month DESC)
        FROM (
          SELECT jsonb_build_object(
            'month', to_char(date_trunc('month', COALESCE(j.entry_date, l.posted_at)), 'YYYY-MM'),
            'debit', COALESCE(SUM(l2.debit_amount), 0),
            'credit', COALESCE(SUM(l2.credit_amount), 0),
            'net', COALESCE(SUM(l2.debit_amount - l2.credit_amount), 0)
          ) AS month_row
          FROM public.ledger l2
          LEFT JOIN public.journals j ON j.id = l2.journal_id
          WHERE l2.rider_id = p_rider_id
          GROUP BY date_trunc('month', COALESCE(j.entry_date, l2.posted_at))
        ) m
      ),
      '[]'::jsonb
    ),
    'categories', COALESCE(
      (
        SELECT jsonb_agg(cat_row)
        FROM (
          SELECT jsonb_build_object(
            'category', COALESCE(j2.category_id, 'uncategorized'),
            'debit', COALESCE(SUM(l3.debit_amount), 0),
            'credit', COALESCE(SUM(l3.credit_amount), 0),
            'net', COALESCE(SUM(l3.debit_amount - l3.credit_amount), 0)
          ) AS cat_row
          FROM public.ledger l3
          LEFT JOIN public.journals j2 ON j2.id = l3.journal_id
          WHERE l3.rider_id = p_rider_id
          GROUP BY COALESCE(j2.category_id, 'uncategorized')
        ) c
      ),
      '[]'::jsonb
    )
  )
  INTO v_payload
  FROM public.ledger l
  LEFT JOIN public.journals j ON j.id = l.journal_id
  WHERE l.rider_id = p_rider_id;

  RETURN COALESCE(v_payload, jsonb_build_object(
    'rider_id', p_rider_id,
    'totals', jsonb_build_object('debit', 0, 'credit', 0, 'net_balance', 0),
    'monthly', '[]'::jsonb,
    'categories', '[]'::jsonb
  ));
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 6) Backward-compatible rider API helper RPCs
-- ============================================================
CREATE OR REPLACE FUNCTION public.rpc_approve_rider_legacy(
  p_rider_id UUID
)
RETURNS VOID AS $$
BEGIN
  UPDATE public.riders
  SET status = 'active'
  WHERE id = p_rider_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.rpc_reject_rider_legacy(
  p_rider_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
  UPDATE public.riders
  SET status = 'retired'
  WHERE id = p_rider_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;





