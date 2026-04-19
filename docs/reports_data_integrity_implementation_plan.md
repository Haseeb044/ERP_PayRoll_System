# Reports Data Integrity Implementation Plan

## Goal
Implement reporting so Profit and Loss is accurate, recoverables are tracked separately, and no double counting happens.

## Accounting Definitions (Lock First)
- Revenue: operational income source currently used by system (finalized payroll-based revenue source).
- Non-recoverable expense: business cost that must hit P&L.
- Recoverable: amount expected back from rider/client; excluded from P&L.

## Current Rule Set To Enforce
- Net Profit = Revenue - NonRecoverableExpenses
- RecoverableOutstanding is shown separately and excluded from P&L.
- RecoverableCollected is shown separately and excluded from P&L.
- Receivable journals use receivable_amount for recovery math, not total_amount.

## File-by-File Checklist

### 1) Repository Aggregation (Single Source of Truth)
File: lib/data/repositories/supabase_report_repository.dart

Tasks:
- Keep P&L expense query based on posted journals only.
- Keep receivable journals excluded from P&L expense.
- Use receivable_amount for recoverable totals.
- Add separate aggregations for:
  - non_recoverable_expense
  - recoverable_outstanding
  - recoverable_collected
- Ensure month filters are identical across all metric queries.
- Add safety guards for null numeric values and malformed rows.

Acceptance:
- No metric is calculated from mixed raw sources for the same accounting bucket.
- Receivable entries do not reduce profit.

### 2) Financial Report Model
File: lib/data/models/financial_report_model.dart

Tasks:
- Add fields:
  - nonRecoverableExpense
  - recoverableOutstanding
  - recoverableCollected
- Keep backward-compatible defaults as 0.0.

Acceptance:
- Existing screens compile and render with default values even before UI update.

### 3) Bloc Mapping and Defaults
File: lib/logic/reports/report_bloc.dart

Tasks:
- Map all new repository fields to model fields with safe fallbacks.
- Keep old keys supported temporarily to avoid breaking older payloads.

Acceptance:
- Reports load even if one optional metric is missing.

### 4) Reports UI Restructure
File: lib/presentation/pages/reports_page.dart

Tasks:
- Keep top KPI for Net Profit based only on P&L inputs.
- Remove duplicate recoverable card if same value already shown in insight summary.
- Add a Non-Recoverable section/card group.
- Add Recovery section/card group with:
  - Recoverable Outstanding
  - Recoverable Collected
- Add helper note under recovery section:
  - "Excluded from P&L."

Acceptance:
- User can visually distinguish P&L vs Recovery metrics at first glance.

### 5) Optional Backend Consistency Hook (If Needed)
File: backend/main.py

Tasks:
- If reports endpoint is used for central aggregation, align payload keys with app model keys.
- Ensure recoverable values are derived from receivable_amount.

Acceptance:
- Flutter and backend return the same accounting meaning for each metric key.

## Data Integrity Safeguards
- Use status = posted for accounting totals.
- Never combine total_amount and receivable_amount in one metric bucket.
- Avoid counting same business event from both expenses and journals simultaneously.
- Use deterministic month boundaries (first day to last day consistently).

## Reconciliation Rules (Must Pass)
- Rule A: non_recoverable_expense + recoverable_excluded + salaries components reconcile to posted expense journals split.
- Rule B: recoverable_outstanding = total_recoverable_created - recoverable_collected.
- Rule C: net_profit remains unchanged when recoverable is created.

## Test Matrix

### Scenario 1: Recoverable Expense Created
Expected:
- P&L expense unchanged.
- Recoverable outstanding increases.

### Scenario 2: Recoverable Partially Collected
Expected:
- P&L unchanged.
- Recoverable outstanding decreases.
- Recoverable collected increases.

### Scenario 3: Vendor Non-Recoverable Expense
Expected:
- Non-recoverable expense increases.
- Net profit decreases.

### Scenario 4: Recoverable Fine
Expected:
- No immediate P&L impact.
- Recovery section reflects outstanding amount.

## Implementation Order (Safe Rollout)
1. Repository changes
2. Model changes
3. Bloc mapping
4. UI restructure
5. Reconciliation checks
6. Scenario validation with one closed month

## Done Criteria
- All scenarios pass.
- No duplicate recoverable metric cards.
- Net profit matches ledger-aligned expected value.
- Business users can explain each card meaning in one sentence.
