import os
from supabase import create_client, Client
from dotenv import load_dotenv

# Try to find .env file
env_path = os.path.join(os.getcwd(), 'backend', '.env')
load_dotenv(env_path)

url: str = os.environ.get("SUPABASE_URL")
key: str = os.environ.get("SUPABASE_KEY")
supabase: Client = create_client(url, key)

RIDER_ID = 'aef50bd2-4914-4140-8c6a-5a1fe81a27fc'

def check():
    print(f"Checking aliases for rider_id: {RIDER_ID}")
    res = supabase.table("rider_aliases").select("*").eq("rider_id", RIDER_ID).execute()
    print("Aliases found:")
    for a in res.data:
        print(f"- ID: {a['id']}, Platform: {a['platform']}, PlatformRiderID: {a['platform_rider_id']}, Status: {a['status']}, ValidTo: {a['valid_to']}")

    res_rider = supabase.table("riders").select("name").eq("id", RIDER_ID).single().execute()
    print(f"Rider Name: {res_rider.data['name']}")

if __name__ == "__main__":
    check()
