# Vendor and Supplier Accounting Workflow (Client Sign-Off Summary)

## 1. Objective

This summary defines how Vendor and Supplier accounting will work in the ERP so transactions remain accurate, transparent, and auditable.

The design separates:
- Profile management (master data)
- Journal posting (accounting instructions)
- Ledger records (financial history)

This prevents data confusion and supports clean audit trails.

---

## 2. Business Rules (Agreed)

1. Vendor and Supplier are separate categories.
2. VAT is applied only for Vendor transactions.
3. Supplier transactions never include VAT.
4. Every posted journal must be balanced (Total Debit = Total Credit).
5. Full and partial payments must update outstanding payables correctly.
6. Corrections must be posted as adjustment/reversal entries, not hidden edits.
7. If a Vendor/Supplier profile does not exist during journal entry, users can create it inline and continue posting.
8. The same party linking model applies to Rider transactions for complete traceability.

---

## 3. Basic Profile Fields (Simple Version)

### Vendor Profile
- id
- vendor_code
- name
- phone
- email
- address
- vat_applicable (default: true)
- vat_no (optional)
- status (active/inactive)
- created_at

### Supplier Profile
- id
- supplier_code
- name
- phone
- email
- address
- vat_applicable (default: false, read-only)
- status (active/inactive)
- created_at

### Minimum Journal Linking
- party_type (vendor/supplier/rider)
- party_id

Meaning of party_id:
- vendor -> vendors.id
- supplier -> suppliers.id
- rider -> riders.id

---

## 4. Journal Screen User Flow

1. Accountant opens Journal Entry.
2. Selects party type: Vendor or Supplier.
3. Selects existing profile from searchable list.
4. If profile is missing, clicks Create New Vendor/Supplier.
5. Profile form opens in popup/inline panel.
6. On save, profile is added and auto-selected.
7. Accountant completes and posts journal.

Validation:
- Posting is not allowed if party type is selected but party profile is missing.
- VAT controls appear only for Vendor.
- VAT controls are hidden/disabled for Supplier.

---

## 5. How Journal and Ledger Work

## Journal
The journal stores accounting instructions for each transaction.
Example: Debit expense, Debit VAT input, Credit vendor payable.

## Ledger
The ledger stores posted accounting impact over time.
Reports, balances, statements, and audits come from ledger data.

Practical meaning:
- Journal = the posting instruction
- Ledger = the posted financial history

---

## 6. Vendor Flow (VAT Applicable)

### Example: Oil purchase
- Base amount: 1,000 AED
- VAT rate: 5%
- VAT amount: 50 AED
- Total payable: 1,050 AED

### Purchase posting entries
- Debit Oil Expense: 1,000
- Debit VAT Input: 50
- Credit Vendor Payable: 1,050

Result:
- Expense recognized correctly
- VAT input captured correctly
- Vendor liability recorded as total payable

### If paid immediately in cash
- Debit Vendor Payable: 1,050
- Credit Cash: 1,050

Result:
- Vendor payable is settled
- Cash decreases

---

## 7. Supplier Flow (No VAT)

### Example: Consultancy fee 2,000 AED

### Purchase posting entries
- Debit Consultancy Expense: 2,000
- Credit Supplier Payable: 2,000

### If paid immediately
- Debit Supplier Payable: 2,000
- Credit Cash/Bank: 2,000

Result:
- Expense recognized
- No VAT entries
- Liability paid or outstanding based on payment timing

---

## 8. Partial Payment Handling

### Example
- Supplier payable created: 2,000
- First payment: 800

Payment entry:
- Debit Supplier Payable: 800
- Credit Cash/Bank: 800

Remaining payable: 1,200

Each additional payment creates a new entry and reduces balance until payable reaches zero.
Previous entries are never overwritten.

---

## 9. Adjustments and Corrections

If a posted amount is wrong:
- Use adjustment entries (difference only), or
- Use reversal + repost

Do not silently modify historical posted rows.

Example VAT correction:
- Wrong VAT posted: 60
- Correct VAT: 50
- Adjustment:
  - Credit VAT Input: 10
  - Debit Vendor Payable (or correction account): 10

This keeps accounting transparent for auditors and management.

---

## 10. Controls, Warnings, and Safety

Must enforce:
- Balanced journals only
- Vendor-only VAT logic
- Supplier no-VAT rule

Warning-first behavior (non-blocking where possible):
- Missing VAT number for taxable vendor
- Unusual VAT values
- Negative net values
- Missing optional reference fields

System should avoid blocking critical work, but never allow impossible accounting states (for example, unbalanced posting).

---

## 11. Final Sign-Off Statement

This workflow provides:
1. Clear separation of Vendor and Supplier accounting.
2. Correct VAT treatment by category.
3. Full journal and ledger transparency.
4. Proper payable tracking for credit and cash scenarios.
5. Support for partial settlements and corrections.
6. Inline profile creation in journal screen for operational speed.
7. Audit-safe posting behavior suitable for ERP governance.
8. Consistent counterparty linking across Vendor, Supplier, and Rider using party_type + party_id.

This scope is ready for client confirmation and phased implementation.
