import os
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

print("Testing upsert without ignore_duplicates")
try:
    # Use the canonical unique column `emirates_id_number` for upsert
    res = supabase.table("riders").upsert({"emirates_id_number": "TEST_EXCEL_999", "name": "Test", "status": "active"}).execute()
    print("RES1:", res.data)
except Exception as e:
    print("ERR1:", type(e).__name__, str(e))

print("\nTesting upsert with ignore_duplicates=True")
try:
    res2 = supabase.table("riders").upsert({"emirates_id_number": "TEST_EXCEL_999", "name": "Test2", "status": "active"}, ignore_duplicates=True).execute()
    print("RES2:", res2.data)
except Exception as e:
    print("ERR2:", type(e).__name__, str(e))

print("\nCleaning up TEST_EXCEL_999")
# Delete by `emirates_id_number`, the column present in the schema
supabase.table("riders").delete().eq("emirates_id_number", "TEST_EXCEL_999").execute()
