from pathlib import Path
from dotenv import load_dotenv
import os
from supabase import create_client
from datetime import datetime
import uuid


def load_supabase():
    env_path = Path(__file__).resolve().parent / '.env'
    load_dotenv(dotenv_path=env_path)
    SUPABASE_URL = os.getenv('SUPABASE_URL')
    SUPABASE_SERVICE_KEY = os.getenv('SUPABASE_SERVICE_KEY')
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        raise RuntimeError(f"Missing Supabase credentials in {env_path}")
    return create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)


def main():
    supabase = load_supabase()

    riders = [
        "Ahmed Mustafa",
        "Rajesh Kumar",
        "Ali Hassan",
        "Muhammad Ali",
        "Omar Farooq",
        "Sara Ahmed",
        "Fatima Noor",
        "Khalid Saeed",
        "Nabil Hassan",
        "Yousef Ibrahim",
        "Hani Alami",
        "Salman Khan",
        "Aisha Siddiqui",
        "Tariq Aziz",
        "Noor Khan",
        "Zainab AlBadi",
        "Hamid Raza",
        "Yasir Qureshi",
        "Bilal Shah",
        "Kareem Osman",
    ]

    print("Upserting test riders...")
    for i, name in enumerate(riders, start=1):
        eid = f"TEST-EID-{i:03}"
        phone = f"+971500{1000 + i}"
        payload = {
            "name": name,
            "emirates_id_number": eid,
            "phone": phone,
            "status": "active"
        }
        try:
            supabase.table("riders").upsert(payload, on_conflict="emirates_id_number").execute()
            print(f"Upserted rider: {name} ({eid})")
        except Exception as e:
            print(f"Failed to upsert rider {name}: {e}")

    # Insert a sample traffic fine (AED 200) for Ahmed Mustafa
    try:
        res = supabase.table("riders").select("id").eq("name", "Ahmed Mustafa").single().execute()
        rider = res.data
        if rider and rider.get("id"):
            fine_payload = {
                "ticket_number": f"TF-{uuid.uuid4().hex[:8]}",
                "plate_number": "TA-TEST-1",
                "violation_date": datetime.utcnow().isoformat(),
                "amount": 200.0,
                "description": "Test traffic fine (AED 200)",
                "city": "Dubai",
                "rider_id": rider.get("id"),
                "status": "unpaid"
            }
            supabase.table("traffic_fines").insert(fine_payload).execute()
            print("Inserted test fine for Ahmed Mustafa (AED 200)")
        else:
            print("Ahmed Mustafa not found; fine not inserted.")
    except Exception as e:
        print(f"Error inserting fine: {e}")

    # Insert an approved expense (AED 50) for Rajesh Kumar
    try:
        res = supabase.table("riders").select("id").eq("name", "Rajesh Kumar").single().execute()
        rider = res.data
        if rider and rider.get("id"):
            expense_payload = {
                "rider_id": rider.get("id"),
                "rider_name": "Rajesh Kumar",
                "expense_type": "Test Expense",
                "amount": 50.0,
                "expense_date": datetime.utcnow().date().isoformat(),
                "description": "Approved test expense (AED 50)",
                "status": "approved",
            }
            supabase.table("expenses").insert(expense_payload).execute()
            print("Inserted approved test expense for Rajesh Kumar (AED 50)")
        else:
            print("Rajesh Kumar not found; expense not inserted.")
    except Exception as e:
        print(f"Error inserting expense: {e}")

    print("Test data setup complete.")


if __name__ == '__main__':
    main()
