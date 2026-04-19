import os
import json
from supabase import create_client, Client
from dotenv import load_dotenv
import uuid

load_dotenv(dotenv_path="E:/Final YearProject/rider_payroll_erp/backend/.env")

url = os.environ.get("SUPABASE_URL")
key = os.environ.get("SUPABASE_SERVICE_KEY")
if not url or not key:
    print("Missing SUPABASE_URL or SUPABASE_SERVICE_KEY")
    exit(1)
supabase: Client = create_client(url, key)

def test_insert():
    try:
        print("Testing DB insert manually to catch Supabase errors...")
        
        # 1. Look up a real rider ID (or just take the first one)
        riders_res = supabase.table("riders").select("id, name").limit(1).execute()
        if not riders_res.data:
            print("No riders found. Please add a rider first.")
            return
            
        rider = riders_res.data[0]
        rider_id = rider["id"]
        rider_name = rider["name"]
        
        print(f"Using Rider: {rider_name} ({rider_id})")
        
        # We also need a valid accountant or PRO user ID for `created_by_user_id` and `changed_by_user_id`
        users_res = supabase.table("profiles").select("id, role").limit(1).execute()
        user_id = users_res.data[0]["id"] if users_res.data else str(uuid.uuid4())
        
        # 1. Test Journal Insert
        journal_id = str(uuid.uuid4())
        journal_data = {
            "id": journal_id,
            "entry_date": "2026-03-12",
            "description": "Other: Test Expense",
            "total_amount": 100.0,
            "status": "draft",
            "type": "expense",
            "created_by_user_id": user_id,
            "created_by_role": "pro",
            "is_receivable": False,
        }
        
        print("\nInserting Journal...")
        res1 = supabase.table("journals").insert(journal_data).execute()
        print("Journal Insert Result:", res1)
        
        # 2. Test Expense Insert
        expense_data = {
            "rider_id": rider_id,
            "rider_name": rider_name,
            "expense_type": "Other",
            "amount": 100.0,
            "expense_date": "2026-03-12",
            "description": "Test Expense",
            "status": "pending",
            "journal_id": journal_id,
            "created_by_role": "pro"
        }
        
        print("\nInserting Expense...")
        res2 = supabase.table("expenses").insert(expense_data).execute()
        print("Expense Insert Result:", res2)
        
        # 3. Test Action Item Insert
        action_item_data = {
            "type": "journal_pending_approval",
            "title": f"Pending Expense: Other",
            "subtitle": f"AED 100.0 • {rider_name}",
            "severity": "warning",
            "route": "/journals",
            "argument_id": journal_id,
            "related_entity": "journal",
            "reference_id": journal_id,
            "responsible_role": "accountant",
        }
        
        print("\nInserting Action Item...")
        res3 = supabase.table("action_items").insert(action_item_data).execute()
        print("Action Item Insert Result:", res3)
        
        print("\nAll inserts successful!")
        
    except Exception as e:
        print(f"\nERROR CAUGHT:")
        print(f"Exception Type: {type(e)}")
        print(f"Exception Message: {str(e)}")

if __name__ == "__main__":
    test_insert()
