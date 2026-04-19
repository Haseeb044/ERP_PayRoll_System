import os
import random
import string
from dotenv import load_dotenv
from supabase import create_client

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '.env'))

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_SERVICE_KEY = os.getenv('SUPABASE_SERVICE_KEY')

if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
    print('Supabase credentials not found in backend/.env')
    raise SystemExit(1)

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

def gen_code(n=8):
    chars = string.ascii_uppercase + string.digits
    return ''.join(random.choice(chars) for _ in range(n))

EMIRATES_ID = 'SEED_TEST_001'
NAME = 'Seed Test Rider'

rider = {
    'emirates_id_number': EMIRATES_ID,
    'name': NAME,
    'status': 'active',
    'rider_code': gen_code(8)
}

print('Upserting test rider:', rider)
res = supabase.table('riders').upsert(rider, on_conflict='emirates_id_number').execute()
print('Result:', res.data)

print('Done.')
