# Vendor and Supplier Accounting Workflow (Client Confirmation Draft)

## 1. Purpose

This document explains how Vendor and Supplier accounting should work in the ERP, including:
- Profile creation flow
- VAT handling rules
- Journal posting logic
- Ledger impact
- Payment scenarios (cash and credit)
- Partial payments and outstanding balances
- Adjustments and audit trail behavior

Goal: keep every financial transaction transparent, accurate, and traceable without blocking business operations.

---

## 2. Core Business Definitions

### 2.1 Vendor
A Vendor is a counterparty where VAT can be applied (for taxable purchases).

Typical examples:
- Oil purchase
- Equipment purchase
- Office supplies

### 2.2 Supplier
A Supplier is a counterparty in a non-VAT flow (as per your business rule).

Typical examples:
- Consultancy fee
- Cleaning service
- Non-taxable service payments

### 2.3 Key Rule
- VAT is allowed only when party type = Vendor.
- VAT is never applied when party type = Supplier.

---

## 3. Profile Model (Basic, Rider-Style)

You requested minimal fields only.

### 3.1 Vendor Basic Fields
- id
- vendor_code
- name
- phone
- email
- address
- vat_applicable (default true)
- vat_no (optional)
- status (active/inactive)
- created_at

### 3.2 Supplier Basic Fields
- id
- supplier_code
- name
- phone
- email
- address
- vat_applicable (default false, read-only)
- status (active/inactive)
- created_at

### 3.3 Journal Link Fields (Minimum)
- party_type (vendor/supplier/rider)
- party_id

### 3.4 Party ID Meaning (Important)
`party_id` is the unique profile ID of the selected counterparty.

- If party_type = vendor, party_id points to vendors.id
- If party_type = supplier, party_id points to suppliers.id
- If party_type = rider, party_id points to riders.id

This keeps every journal and ledger row linked to the exact profile for statements, balances, and audits.

---

## 4. UX Flow in Journal Screen (Your Required Behavior)

### 4.1 Inline Profile Selection and Creation
Inside Journal Entry form:
1. User selects `party_type` (Vendor or Supplier).
2. User selects existing profile from searchable dropdown.
3. If profile does not exist, user clicks `Create New Vendor` or `Create New Supplier`.
4. Profile mini-form opens (same screen/modal flow).
5. On save, new profile is inserted into master table.
6. Dropdown refreshes and auto-selects newly created profile.
7. User completes journal posting.

### 4.2 Validation Rules
- If party type is chosen, profile must be selected before posting.
- If Vendor selected and VAT enabled, VAT calculation must be validated.
- Supplier flow must not allow VAT lines.
- Duplicate-name warning can be shown, but posting should not be hard blocked unless policy requires exact uniqueness.

---

## 5. Accounting Architecture (How Data Moves)

Use separate layers for clean accounting:

1. **Master Data Layer**
- vendors table
- suppliers table

2. **Transaction Layer**
- journal_entries (header)
- journal_lines (debit/credit lines)

3. **Ledger Layer**
- ledger_entries generated from posted journal lines

4. **Reference Linking**
- every relevant journal and ledger row includes party_type + party_id when applicable (vendor/supplier/rider)

This keeps profile data separate from financial postings while preserving full traceability.

---

## 6. Journal vs Ledger (Simple Explanation)

### 6.1 Journal
Journal is the accounting instruction set for a transaction.
- Example: debit expense, debit VAT input, credit vendor payable.
- Journal must balance: total debit = total credit.

### 6.2 Ledger
Ledger is the posted financial history from journals.
- Used for balances, statements, aging, audit, and reporting.
- Never rewrite old posted entries; corrections should be new adjustment/reversal entries.

### 6.3 Practical Meaning
- Journal = what was posted.
- Ledger = cumulative financial truth after posting.

---

## 7. Vendor Purchase with VAT (Detailed)

## 7.1 Scenario
- Party type: Vendor
- Base amount: 1,000 AED
- VAT rate: 5%
- VAT amount: 50 AED
- Total payable: 1,050 AED

### 7.2 Journal Lines at Purchase Posting
1. Debit Expense Account: 1,000
2. Debit VAT Input Account: 50
3. Credit Vendor Payable: 1,050

Check:
- Total Debit = 1,050
- Total Credit = 1,050
- Balanced = Yes

### 7.3 Ledger Impact
- Expense increases by 1,000
- Recoverable VAT input increases by 50
- Liability to vendor increases by 1,050

---

## 8. Supplier Purchase (No VAT)

### 8.1 Scenario
- Party type: Supplier
- Amount: 2,000 AED
- VAT: Not applicable

### 8.2 Journal Lines
1. Debit Consultancy Expense: 2,000
2. Credit Supplier Payable: 2,000

### 8.3 Ledger Impact
- Expense increases by 2,000
- Liability to supplier increases by 2,000

---

## 9. Payment Flow (Cash vs Credit)

## 9.1 Credit Purchase
At purchase time:
- Cash does not move.
- Payable increases.

This means amount is outstanding until payment transaction is posted.

## 9.2 Immediate Cash Payment
After payable exists, payment posting should be:
1. Debit Vendor/Supplier Payable
2. Credit Cash/Bank

Effect:
- Liability decreases
- Cash/Bank decreases

### Example (Vendor total 1,050)
1. Debit Vendor Payable: 1,050
2. Credit Cash: 1,050

Net result after purchase + payment:
- Expense remains recognized
- VAT remains recognized (vendor case)
- Payable clears to zero
- Cash reduced

---

## 10. Partial Payments

### 10.1 Scenario
Supplier payable = 2,000
First payment = 800
Remaining = 1,200

### 10.2 Payment Journal
1. Debit Supplier Payable: 800
2. Credit Cash/Bank: 800

### 10.3 Balance Behavior
- Supplier outstanding automatically becomes 1,200.
- ERP should show paid amount, remaining amount, and due status.

### 10.4 Multiple Partial Payments
Every payment creates a new journal + ledger entry.
Do not overwrite previous payment rows.

---

## 11. Adjustments, Corrections, and Reversals

### 11.1 Rule
Never silently edit posted financial history.

Use one of these patterns:
1. **Adjustment entry** (difference only)
2. **Reversal + repost** (if full correction needed)

### 11.2 Example: VAT correction
If VAT was wrongly posted 60 instead of 50:
- Credit VAT Input: 10
- Debit Vendor Payable (or correction account): 10

All corrections remain visible in audit trail.

---

## 12. Audit Trail and Transparency Requirements

For every purchase/payment/adjustment, store:
- transaction number
- posting date
- party_type + party_id
- source document reference (invoice/bill/payment no)
- created_by, posted_by
- approval status
- timestamp
- narration/remarks
- reversal_of_entry_id (if correction)

This allows accountants to track who did what, when, and why.

Note: the same linking model is used for riders so rider-related deductions, penalties, reimbursements, and settlements remain traceable per rider profile.

---

## 13. Data Integrity and Safety Rules

### 13.1 Must Always Enforce
- Journal must balance (debit = credit).
- Vendor VAT logic only in Vendor category.
- Supplier flow must not produce VAT lines.
- Posted entries should not be physically edited without audit-safe mechanism.

### 13.2 Warning-First (Do Not Block Critical Ops)
If inconsistencies are detected, show warnings instead of hard-blocking all operations:
- negative net amount
- missing VAT number for VAT vendor
- unusually high VAT
- missing counterparty

But always prevent impossible accounting states (for example unbalanced journal).

---

## 14. Suggested Posting Templates

### 14.1 Vendor Purchase (VAT)
- Dr Expense = Base
- Dr VAT Input = VAT
- Cr Vendor Payable = Base + VAT

### 14.2 Vendor Payment
- Dr Vendor Payable = Paid amount
- Cr Cash/Bank = Paid amount

### 14.3 Supplier Purchase (No VAT)
- Dr Expense = Amount
- Cr Supplier Payable = Amount

### 14.4 Supplier Payment
- Dr Supplier Payable = Paid amount
- Cr Cash/Bank = Paid amount

---

## 15. End-to-End Practical Examples

## Example A: Vendor oil purchase (cash later)
Purchase:
- Dr Oil Expense 1,000
- Dr VAT Input 50
- Cr Vendor Payable 1,050

Payment:
- Dr Vendor Payable 1,050
- Cr Cash 1,050

Result:
- Expense recognized correctly
- VAT tracked correctly
- Payable settled
- Cash reduced correctly

## Example B: Supplier consultancy with partial payments
Purchase:
- Dr Consultancy Expense 2,000
- Cr Supplier Payable 2,000

Payment 1:
- Dr Supplier Payable 800
- Cr Cash 800
Remaining payable: 1,200

Payment 2:
- Dr Supplier Payable 1,200
- Cr Cash 1,200
Remaining payable: 0

---

## 16. Implementation Scope Proposal (Phased)

### Phase 1 (MVP)
- Basic vendor/supplier profile tables
- Inline create/select in journal form
- Vendor VAT logic
- Supplier non-VAT logic
- Posting to journal + ledger
- Partial payment support

### Phase 2
- Advanced validations
- Aging and payable reports
- Approval workflow enhancements
- Reversal workflows and correction helpers

---

## 17. Final Confirmation Summary for Client

1. Vendor and Supplier are handled separately.
2. VAT applies only to Vendor flow.
3. Every posting generates balanced journal entries.
4. Ledger reflects all posted transactions for transparency.
5. Payments (full/partial) reduce payables correctly.
6. Adjustments are audit-safe (no hidden history edits).
7. Users can create profile inline during journal posting if missing.

For rider transactions, the same party_type + party_id design applies using party_type = rider and party_id = riders.id.

This design is accounting-safe, practical for daily operations, and ready for controlled ERP implementation.
