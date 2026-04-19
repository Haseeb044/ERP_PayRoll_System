"""
setup_users.py
==============
Creates the two default ERP users via Supabase GoTrue Admin API.

This correctly populates BOTH:
  - auth.users      (email + hashed password + identities)
  - public.users    (id, email, role — via the auto-sync trigger)

PREREQUISITE: Run seed_users.sql in Supabase SQL Editor FIRST!
              That file deletes broken rows, fixes constraints,
              RLS policies, and creates the auto-sync trigger.

Usage:
  cd scripts
  pip install requests python-dotenv
  python setup_users.py
"""

import os
import sys
import json
import urllib3
import requests
from pathlib import Path

# Suppress SSL warnings (cert date mismatch on dev machine)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Load .env
try:
    from dotenv import load_dotenv
    env_path = Path(__file__).resolve().parent.parent / "backend" / ".env"
    load_dotenv(dotenv_path=env_path)
except ImportError:
    pass

# Supabase credentials (must come from environment variables)
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

if not SUPABASE_URL or not SERVICE_KEY:
    print("ERROR: Missing SUPABASE_URL and/or SUPABASE_SERVICE_KEY in environment.")
    sys.exit(1)

HEADERS = {
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
}

# Users to create
USERS = [
    {
        "email": "accountant@erp.com",
        "password": "Accountant123!",
        "role": "ACCOUNTANT",
    },
    {
        "email": "pro@erp.com",
        "password": "Pro123!",
        "role": "PRO",
    },
]


def check_gotrue_health():
    """Verify GoTrue is responsive."""
    r = requests.get(f"{SUPABASE_URL}/auth/v1/health",
                     headers={"apikey": SERVICE_KEY}, verify=False)
    if r.status_code != 200:
        print(f"  ERROR: GoTrue not healthy: {r.status_code} {r.text[:200]}")
        return False
    print(f"  GoTrue healthy (v{r.json().get('version', '?')})")
    return True


def check_gotrue_can_list():
    """Check if GoTrue can list users (fails if broken rows exist)."""
    r = requests.get(f"{SUPABASE_URL}/auth/v1/admin/users?page=1&per_page=1",
                     headers=HEADERS, verify=False)
    if r.status_code == 200:
        return True
    print(f"  ERROR: GoTrue cannot list users: {r.status_code}")
    print(f"  {r.text[:300]}")
    print()
    print("  >>> You must run seed_users.sql in Supabase SQL Editor first! <<<")
    print("  >>> That file deletes the broken manually-inserted rows.      <<<")
    return False


def delete_existing_user(email):
    """Delete user by email if it exists."""
    r = requests.get(f"{SUPABASE_URL}/auth/v1/admin/users?page=1&per_page=100",
                     headers=HEADERS, verify=False)
    if r.status_code != 200:
        return

    data = r.json()
    users = data.get("users", data) if isinstance(data, dict) else data
    if not isinstance(users, list):
        return

    for u in users:
        if u.get("email") == email:
            uid = u["id"]
            print(f"  Deleting existing user {uid[:8]}...")
            r2 = requests.delete(f"{SUPABASE_URL}/auth/v1/admin/users/{uid}",
                                 headers=HEADERS, verify=False)
            if r2.status_code in (200, 204):
                print(f"  Deleted.")
                requests.delete(
                    f"{SUPABASE_URL}/rest/v1/users?id=eq.{uid}",
                    headers=HEADERS, verify=False
                )
            else:
                print(f"  Delete failed: {r2.status_code} {r2.text[:100]}")


def create_user(email, password, role):
    """Create user via GoTrue Admin API."""
    payload = {
        "email": email,
        "password": password,
        "email_confirm": True,
        "user_metadata": {"role": role},
    }

    r = requests.post(f"{SUPABASE_URL}/auth/v1/admin/users",
                      headers=HEADERS, json=payload, verify=False)

    if r.status_code in (200, 201):
        data = r.json()
        uid = data.get("id", "?")
        print(f"  Created: {uid}")
        return uid
    elif r.status_code == 422 and "already" in r.text.lower():
        print(f"  Already exists, deleting and recreating...")
        delete_existing_user(email)
        r2 = requests.post(f"{SUPABASE_URL}/auth/v1/admin/users",
                           headers=HEADERS, json=payload, verify=False)
        if r2.status_code in (200, 201):
            uid = r2.json().get("id", "?")
            print(f"  Recreated: {uid}")
            return uid
        else:
            print(f"  Retry failed: {r2.status_code} {r2.text[:200]}")
            return None
    else:
        print(f"  ERROR: {r.status_code} {r.text[:300]}")
        return None


def verify_public_users(uid, email):
    """Check that the auto-sync trigger created the public.users row."""
    r = requests.get(
        f"{SUPABASE_URL}/rest/v1/users?select=id,email,role&id=eq.{uid}",
        headers=HEADERS, verify=False
    )
    if r.status_code == 200:
        data = r.json()
        if data:
            print(f"  public.users: {data[0]}")
        else:
            print(f"  WARNING: No row in public.users for {email}")
            print(f"  (The handle_new_user trigger may not have fired)")
    else:
        print(f"  Verify failed: {r.status_code} {r.text[:100]}")


def test_sign_in(email, password):
    """Test signing in with the created credentials."""
    r = requests.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        headers={"apikey": ANON_KEY, "Content-Type": "application/json"},
        json={"email": email, "password": password},
        verify=False
    )
    if r.status_code == 200:
        token = r.json().get("access_token", "")[:20]
        print(f"  Sign-in OK (token: {token}...)")
        return True
    else:
        print(f"  Sign-in FAILED: {r.status_code} {r.text[:200]}")
        return False


def main():
    print("=" * 60)
    print("  RIDER PAYROLL ERP — User Setup")
    print("=" * 60)
    print(f"  URL: {SUPABASE_URL}")
    print()

    # Pre-flight checks
    print("Pre-flight checks:")
    if not check_gotrue_health():
        sys.exit(1)
    if not check_gotrue_can_list():
        sys.exit(1)
    print()

    # Create users
    for user_data in USERS:
        email = user_data["email"]
        password = user_data["password"]
        role = user_data["role"]

        print(f"--- {role}: {email} ---")

        delete_existing_user(email)
        uid = create_user(email, password, role)
        if uid is None:
            print(f"  SKIPPED\n")
            continue

        verify_public_users(uid, email)
        test_sign_in(email, password)
        print()

    # Final summary
    print("=" * 60)
    print("  CREDENTIALS")
    print("=" * 60)
    print("  ACCOUNTANT: accountant@erp.com / Accountant123!")
    print("  PRO:        pro@erp.com        / Pro123!")
    print("=" * 60)
    print()
    print("  You can now log in from the Flutter app!")


if __name__ == "__main__":
    main()
