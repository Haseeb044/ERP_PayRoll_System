import uuid
from datetime import datetime

# Mock clean_platform_id for testing
def clean_platform_id(raw_id: any) -> str:
    return str(raw_id).strip()

# The function to test (copied from main.py after my edits)
def resolve_rider_alias_optimized(
    platform_id: str, 
    platform: str, 
    rider_name: str, 
    payroll_month: str, 
    batch_id: str, 
    payslip_id: str,
    pre_fetched_aliases: dict,
    pre_fetched_riders: dict,
    rider_to_active_alias: dict,
    global_alias_map: dict = None,
):
    try:
        platform = platform.lower()
        cleaned_id = clean_platform_id(platform_id)
        
        if not cleaned_id:
            return None, None, None, "Missing Platform ID", None, None, "ERROR"

        # --- Strict Platform Check (New Requirement) ---
        platform_aliases = pre_fetched_aliases.get(cleaned_id, [])
        
        # If no alias on CURRENT platform, check if ID exists on OTHER platforms
        if not platform_aliases and global_alias_map:
            global_match = global_alias_map.get(cleaned_id)
            if global_match:
                db_platform = global_match.get("platform", "Unknown")
                return global_match.get("rider_id"), None, rider_name, f"Cross-platform: {db_platform}", None, None, "SKIP"

        if active_alias := next((a for a in platform_aliases if a["status"] == "active" and a["valid_to"] is None), None):
            r_name = (active_alias.get("rider") or {}).get("name") or rider_name
            r_status = (active_alias.get("rider") or {}).get("status") or "active"
            return active_alias["rider_id"], active_alias["id"], r_name, r_status, None, None, "MATCHED"

        # (Other steps truncated for brevity in this simple test)
        error_msg = f"Rider ID {cleaned_id} not found."
        return None, None, None, error_msg, None, None, "ERROR"

    except Exception as e:
        return None, None, None, f"System Resolve Error: {str(e)}", None, None, "ERROR"

# --- TEST CASES ---

# Setup test data
pre_fetched_aliases = {
    "101": [{"id": "alias_id_101", "rider_id": "rider_uuid_101", "status": "active", "valid_to": None, "rider": {"name": "Talabat Rider"}}]
}
global_alias_map = {
    "202": {"platform": "keeta", "rider_id": "rider_uuid_202"}
}

print("Running Test Case 1: Valid Platform Match (Talabat -> Talabat)")
res = resolve_rider_alias_optimized("101", "Talabat", "Rider X", "2025-12", "batch_1", "slip_1", pre_fetched_aliases, {}, {}, global_alias_map)
assert res[6] == "MATCHED"
print("SUCCESS: 101 matched on Talabat.")

print("\nRunning Test Case 2: Cross-platform Skip (Keeta Rider in Talabat Sheet)")
res = resolve_rider_alias_optimized("202", "Talabat", "Rider Y", "2025-12", "batch_1", "slip_1", pre_fetched_aliases, {}, {}, global_alias_map)
assert res[6] == "SKIP"
assert "keeta" in res[3].lower()
print("SUCCESS: 202 skipped as cross-platform (Keeta).")

print("\nRunning Test Case 3: Truly Missing Rider (Error)")
res = resolve_rider_alias_optimized("303", "Talabat", "Rider Z", "2025-12", "batch_1", "slip_1", pre_fetched_aliases, {}, {}, global_alias_map)
assert res[6] == "ERROR"
print("SUCCESS: 303 marked as error.")
