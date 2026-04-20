from fastapi import FastAPI, HTTPException, Depends, BackgroundTasks, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from supabase import create_client, Client
import requests
import re
import uuid
import os
from pathlib import Path
from dotenv import load_dotenv
# import pandas as pd
from fastapi import UploadFile, File
from io import BytesIO
import pandas as pd
from dateutil.parser import parse as parse_date
from datetime import timedelta
from concurrent.futures import ThreadPoolExecutor
from threading import Lock

# Explicitly load .env from the backend directory
env_path = Path(__file__).resolve().parent / '.env'
load_dotenv(dotenv_path=env_path)

# Debug: Print the path being checked (optional, for verification)
print(f"Loading .env from: {env_path}")

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY")
JOURNAL_REVERSAL_TIMELOCK_DAYS = int(os.getenv("JOURNAL_REVERSAL_TIMELOCK_DAYS", "0") or "0")
ALLOWED_LOGIN_IPS_RAW = os.getenv("ALLOWED_LOGIN_IPS", "")
ALLOWED_LOGIN_IPS = {
    ip.strip() for ip in ALLOWED_LOGIN_IPS_RAW.split(",") if ip.strip()
}

if not SUPABASE_URL:
    raise RuntimeError(f"Supabase credentials not found. Checked path: {env_path}")

app = FastAPI()
security = HTTPBearer()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)



supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

class RiderCreate(BaseModel):
    rider_id: str | None = None
    name: str
    emirates_id_number: str
    phone: str | None = None
    city: str | None = None
    status: str | None = "active"
    passport_number: str | None = None
    wps_status: str | None = "WPS"
    release_hold: str | None = "release"
    created_by_user_id: str | None = None
    passport_expiry_date: str | None = None
    emirates_id_expiry_date: str | None = None
    visa_expiry_date: str | None = None
    hold_reason: str | None = None
    hold_until: str | None = None

class LoginRequest(BaseModel):
    email: str
    password: str


class DrawerTopupRequest(BaseModel):
    amount: float
    target_type: str  # "noqodi" or "petty_cash"


class TransactionCreate(BaseModel):
    rider_id: str | None = None
    from_drawer: str  # Frontend sends "bank", "noqodi", "petty_cash"; resolved to drawer_id internally
    amount: float
    reason: str  # e.g., 'government_legal', 'loans_advances', 'operational_expenses'


# Drawer name mapping: frontend identifier → DB drawer name (new schema uses seeded names)
DRAWER_FRONTEND_TO_DB = {
    "noqodi": "Noqodi",
    "petty_cash": "Cash",
    "bank": "Bank",
}
DRAWER_DB_TO_FRONTEND = {v: k for k, v in DRAWER_FRONTEND_TO_DB.items()}


class BikeCreate(BaseModel):
    bike_id: str
    model: str | None = None
    chassis_number: str | None = None

class BikeAssignRequest(BaseModel):
    rider_id: str
    chassis_number: str

class BikeAssignmentCreate(BaseModel):
    rider_id: str
    chassis_number: str

from datetime import datetime

class PlatformIdRequest(BaseModel):
    platform_id: str

class FineCreate(BaseModel):
    ticket_number: str
    plate_number: str
    violation_date: str  # Format: YYYY-MM-DD
    violation_time: str  # Format: HH:MM
    amount: float
    description: str | None = None
    city: str | None = "Dubai"
    rider_name: str | None = None  # Optional: rider name from Excel for name-based matching
    plus_amount: float | None = None
    remaining_balance: float | None = None

class ExpenseStatusUpdate(BaseModel):
    status: str

class ExpenseCreate(BaseModel):
    rider_id: str
    expense_type: str
    amount: float
    expense_date: str  # Format: YYYY-MM-DD
    description: str | None = None
    status: str | None = "pending"
    receipt_url: str | None = None
    category_id: str | None = None

class JournalApprovalRequest(BaseModel):
    drawer_id: str
    payment_method: str
    is_receivable: bool = False
    receivable_amount: float | None = None
    lines: list = []  # list of {account_id, debit_amount, credit_amount, drawer_id?}

class FineBulkUploadRequest(BaseModel):
    fines: list[FineCreate]

class FineAssignRequest(BaseModel):
    rider_id: str

class BulkStatusRequest(BaseModel):
    ids: list[str]
    status: str

class ActionDismissalRequest(BaseModel):
    action_id: str
    reason: str | None = "Dismissed by user"


class RiderApprovalRequest(BaseModel):
    rider_id: str
    action_item_id: str | None = None


class RiderRejectionRequest(BaseModel):
    rider_id: str
    reason: str | None = None
    action_item_id: str | None = None


class RiderStatusUpdateRequest(BaseModel):
    status: str
    reason: str | None = None
    effective_from: str | None = None
    expected_return_date: str | None = None


class RiderReleaseHoldRequest(BaseModel):
    release_hold: str
    reason: str | None = None
    hold_until: str | None = None


class RiderAliasPreviewRequest(BaseModel):
    platform: str
    platform_rider_id: str
    valid_from: str | None = None


class VendorCreate(BaseModel):
    name: str
    phone: str | None = None
    email: str | None = None
    address: str | None = None
    vat_applicable: bool = True
    vat_no: str | None = None
    status: str = "active"


class SupplierCreate(BaseModel):
    name: str
    phone: str | None = None
    email: str | None = None
    address: str | None = None
    status: str = "active"


def write_audit_log(table_name: str, record_id: str, action: str, old_data=None, new_data=None, user_id=None):
    """Helper to write an entry to the audit_log table."""
    try:
        import json
        entry = {
            "table_name": table_name,
            "record_id": record_id,
            "action": action,
        }
        if old_data is not None:
            entry["old_data"] = json.dumps(old_data) if not isinstance(old_data, str) else old_data
        if new_data is not None:
            entry["new_data"] = json.dumps(new_data) if not isinstance(new_data, str) else new_data
        if user_id:
            entry["changed_by_user_id"] = user_id
        supabase.table("audit_log").insert(entry).execute()
    except Exception as e:
        print(f"Warning: audit_log write failed: {e}")

def get_user_from_token(token: str):
    headers = {
        "Authorization": f"Bearer {token}",
        "apikey": SUPABASE_ANON_KEY
    }

    response = requests.get(
        f"{SUPABASE_URL}/auth/v1/user",
        headers=headers
    )

    if response.status_code != 200:
        raise HTTPException(status_code=401, detail="Invalid token")

    return response.json()


def get_user_role(user_id: str):
    res = supabase.table("profiles") \
        .select("role") \
        .eq("id", user_id) \
        .single() \
        .execute()

    if not res.data:
        raise HTTPException(status_code=404, detail="Profile not found")

    return res.data["role"]

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    token = credentials.credentials

    user = get_user_from_token(token)
    role = get_user_role(user["id"])

    return {
        "id": user["id"],
        "role": role
    }


def require_role(required_roles: str | list[str]):
    if isinstance(required_roles, str):
        required_roles = [required_roles]
        
    def role_checker(user = Depends(get_current_user)):
        user_role = str(user.get("role", "")).lower()
        req_roles = [r.lower() for r in required_roles]
        if user_role not in req_roles:
            raise HTTPException(
                status_code=403,
                detail=f"Forbidden: Requires one of {required_roles} (found {user_role})"
            )
        return user
    return role_checker


def _request_client_meta(request: Request) -> dict:
    forwarded = request.headers.get("x-forwarded-for", "").strip()
    forwarded_ip = forwarded.split(",")[0].strip() if forwarded else None
    real_ip = request.headers.get("x-real-ip", "").strip() or None
    direct_ip = request.client.host if request.client else None
    return {
        "ip": forwarded_ip or real_ip or direct_ip,
        "user_agent": request.headers.get("user-agent"),
        "device_id": request.headers.get("x-device-id"),
        "platform": request.headers.get("sec-ch-ua-platform"),
    }


@app.post("/login")
def login(data: LoginRequest, request: Request):
    client_meta = _request_client_meta(request)

    if ALLOWED_LOGIN_IPS:
        request_ip = (client_meta.get("ip") or "").strip()
        if request_ip not in ALLOWED_LOGIN_IPS:
            write_audit_log(
                table_name="auth_sessions",
                record_id=str(uuid.uuid4()),
                action="LOGIN_BLOCKED_IP",
                new_data={
                    "email": data.email,
                    "allowed_ips": sorted(ALLOWED_LOGIN_IPS),
                    **client_meta,
                },
                user_id=None,
            )
            raise HTTPException(status_code=403, detail="Login blocked from this IP")

    payload = {
        "email": data.email,
        "password": data.password,
    }

    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
    }

    response = requests.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        json=payload,
        headers=headers,
    )

    if response.status_code != 200:
        # Keep minimal failed-login trace for security visibility.
        write_audit_log(
            table_name="auth_sessions",
            record_id=str(uuid.uuid4()),
            action="LOGIN_FAILED",
            new_data={
                "email": data.email,
                **client_meta,
            },
            user_id=None,
        )
        raise HTTPException(status_code=401, detail="Invalid email or password")

    auth_data = response.json()
    user_id = (auth_data.get("user") or {}).get("id")

    write_audit_log(
        table_name="auth_sessions",
        record_id=str(uuid.uuid4()),
        action="LOGIN_SUCCESS",
        new_data={
            "email": data.email,
            **client_meta,
        },
        user_id=user_id,
    )

    # Return the token response from Supabase (includes access_token, refresh_token, etc.)
    return auth_data


@app.post("/logout")
def logout(
    request: Request,
    credentials: HTTPAuthorizationCredentials = Depends(security),
):
    token = credentials.credentials

    user_id = None
    try:
        user_id = get_user_from_token(token).get("id")
    except Exception:
        user_id = None

    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {token}",
    }

    response = requests.post(
        f"{SUPABASE_URL}/auth/v1/logout",
        headers=headers,
    )

    if response.status_code not in (200, 204):
        raise HTTPException(status_code=400, detail="Logout failed")

    write_audit_log(
        table_name="auth_sessions",
        record_id=str(uuid.uuid4()),
        action="LOGOUT",
        new_data=_request_client_meta(request),
        user_id=user_id,
    )

    return {"message": "Logged out successfully"}



@app.get("/me")
def read_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials  

    user = get_user_from_token(token)
    role = get_user_role(user["id"])

    return {
        "user_id": user["id"],
        "role": role
    }

class DynamicExcelUploadRequest(BaseModel):
    rows: list[dict]

@app.post("/excel/upload-dynamic")
def upload_dynamic_excel(
    data: DynamicExcelUploadRequest,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    """
    Takes an array of dictionaries representing Excel rows.
    Handles Rider creation/updates, Bike updates (by Chassis), and strictly manages assignments.
    """
    rows = data.rows
    if not rows:
        return {"message": "No rows provided", "processed": 0}

    # Header Mapping Dictionary: Maps Excel labels to Database columns
    MAPPING = {
        # RIDERS TABLE
        "emirates id": {"table": "riders", "column": "emirates_id_number"},
        "emirates id no": {"table": "riders", "column": "emirates_id_number"},
        "emirates id number": {"table": "riders", "column": "emirates_id_number"},
        "emirates_id_number": {"table": "riders", "column": "emirates_id_number"},
        "emirate id": {"table": "riders", "column": "emirates_id_number"},
        "eid": {"table": "riders", "column": "emirates_id_number"},
        "eid no": {"table": "riders", "column": "emirates_id_number"},
        "eid number": {"table": "riders", "column": "emirates_id_number"},
        "eid_no": {"table": "riders", "column": "emirates_id_number"},
        "national id": {"table": "riders", "column": "emirates_id_number"},
        "national_id": {"table": "riders", "column": "emirates_id_number"},
        "resident id": {"table": "riders", "column": "emirates_id_number"},
        "identity number": {"table": "riders", "column": "emirates_id_number"},
        "id number": {"table": "riders", "column": "emirates_id_number"},
        "id_number": {"table": "riders", "column": "emirates_id_number"},
        "uidentity": {"table": "riders", "column": "emirates_id_number"},
        "name": {"table": "riders", "column": "name"},
        "full name": {"table": "riders", "column": "name"},
        "fullname": {"table": "riders", "column": "name"},
        "rider name": {"table": "riders", "column": "name"},
        "rider_name": {"table": "riders", "column": "name"},
        "courier name": {"table": "riders", "column": "name"},
        "employee name": {"table": "riders", "column": "name"},
        "employee_name": {"table": "riders", "column": "name"},
        "staff name": {"table": "riders", "column": "name"},
        "staff_name": {"table": "riders", "column": "name"},
        "rider": {"table": "riders", "column": "name"},
        "courier": {"table": "riders", "column": "name"},
        "phone": {"table": "riders", "column": "phone"},
        "phone number": {"table": "riders", "column": "phone"},
        "phone_no": {"table": "riders", "column": "phone"},
        "mobile": {"table": "riders", "column": "phone"},
        "mobile no": {"table": "riders", "column": "phone"},
        "mobile_no": {"table": "riders", "column": "phone"},
        "contact": {"table": "riders", "column": "phone"},
        "contact number": {"table": "riders", "column": "phone"},
        "telephone": {"table": "riders", "column": "phone"},
        "cell number": {"table": "riders", "column": "phone"},
        "city": {"table": "riders", "column": "city"},
        "passport": {"table": "riders", "column": "passport_number"},
        "passport number": {"table": "riders", "column": "passport_number"},
        "passport_number": {"table": "riders", "column": "passport_number"},
        "status": {"table": "riders", "column": "status"},
        "wps status": {"table": "riders", "column": "wps_status"},
        "wps_status": {"table": "riders", "column": "wps_status"},
        "release hold": {"table": "riders", "column": "release_hold"},
        "release_hold": {"table": "riders", "column": "release_hold"},
        "rider_code": {"table": "riders", "column": "rider_code"},
        "code": {"table": "riders", "column": "rider_code"},
        # Expiry / compliance date aliases (optional fields)
        "passport expiry": {"table": "riders", "column": "passport_expiry_date"},
        "passport expiry date": {"table": "riders", "column": "passport_expiry_date"},
        "passport exp": {"table": "riders", "column": "passport_expiry_date"},
        "passport exp date": {"table": "riders", "column": "passport_expiry_date"},
        "passport valid till": {"table": "riders", "column": "passport_expiry_date"},
        "passport valid until": {"table": "riders", "column": "passport_expiry_date"},
        "passport_expiry": {"table": "riders", "column": "passport_expiry_date"},
        "passport_expiry_date": {"table": "riders", "column": "passport_expiry_date"},
        "passport expiry dt": {"table": "riders", "column": "passport_expiry_date"},
        "pp expiry": {"table": "riders", "column": "passport_expiry_date"},
        "pp exp": {"table": "riders", "column": "passport_expiry_date"},

        "emirates id expiry": {"table": "riders", "column": "emirates_id_expiry_date"},
        "emirates id expiry date": {"table": "riders", "column": "emirates_id_expiry_date"},
        "emirates id exp": {"table": "riders", "column": "emirates_id_expiry_date"},
        "eid expiry": {"table": "riders", "column": "emirates_id_expiry_date"},
        "eid expiry date": {"table": "riders", "column": "emirates_id_expiry_date"},
        "eid exp": {"table": "riders", "column": "emirates_id_expiry_date"},
        "id expiry": {"table": "riders", "column": "emirates_id_expiry_date"},
        "id expiry date": {"table": "riders", "column": "emirates_id_expiry_date"},
        "national id expiry": {"table": "riders", "column": "emirates_id_expiry_date"},
        "emirates_id_expiry": {"table": "riders", "column": "emirates_id_expiry_date"},
        "emirates_id_expiry_date": {"table": "riders", "column": "emirates_id_expiry_date"},
        "eid_expiry": {"table": "riders", "column": "emirates_id_expiry_date"},
        "eid_expiry_date": {"table": "riders", "column": "emirates_id_expiry_date"},

        "visa expiry": {"table": "riders", "column": "visa_expiry_date"},
        "visa expiry date": {"table": "riders", "column": "visa_expiry_date"},
        "visa exp": {"table": "riders", "column": "visa_expiry_date"},
        "visa exp date": {"table": "riders", "column": "visa_expiry_date"},
        "visa valid till": {"table": "riders", "column": "visa_expiry_date"},
        "visa valid until": {"table": "riders", "column": "visa_expiry_date"},
        "visa_expiry": {"table": "riders", "column": "visa_expiry_date"},
        "visa_expiry_date": {"table": "riders", "column": "visa_expiry_date"},
        "residence visa expiry": {"table": "riders", "column": "visa_expiry_date"},
        "residency visa expiry": {"table": "riders", "column": "visa_expiry_date"},
        "visa due date": {"table": "riders", "column": "visa_expiry_date"},

        "hold reason": {"table": "riders", "column": "hold_reason"},
        "hold_reason": {"table": "riders", "column": "hold_reason"},
        "block reason": {"table": "riders", "column": "hold_reason"},
        "hold until": {"table": "riders", "column": "hold_until"},
        "hold until date": {"table": "riders", "column": "hold_until"},
        "hold till": {"table": "riders", "column": "hold_until"},
        "hold_till": {"table": "riders", "column": "hold_until"},
        "hold_until": {"table": "riders", "column": "hold_until"},
        "block until": {"table": "riders", "column": "hold_until"},
        "blocked till": {"table": "riders", "column": "hold_until"},
        
        # BIKES TABLE
        "chassis": {"table": "bikes", "column": "chassis_number"},
        "chassis number": {"table": "bikes", "column": "chassis_number"},
        "chassis_number": {"table": "bikes", "column": "chassis_number"},
        "chassis_no": {"table": "bikes", "column": "chassis_number"},
        "vin": {"table": "bikes", "column": "chassis_number"},
        "serial number": {"table": "bikes", "column": "chassis_number"},
        "serial_no": {"table": "bikes", "column": "chassis_number"},
        "chasis": {"table": "bikes", "column": "chassis_number"},
        "vehicle serial": {"table": "bikes", "column": "chassis_number"},
        "frame number": {"table": "bikes", "column": "chassis_number"},
        "plate": {"table": "bikes", "column": "bike_id"},
        "plate number": {"table": "bikes", "column": "bike_id"},
        "plate_number": {"table": "bikes", "column": "bike_id"},
        "plate no": {"table": "bikes", "column": "bike_id"},
        "plate_no": {"table": "bikes", "column": "bike_id"},
        "bike id": {"table": "bikes", "column": "bike_id"},
        "bike_id": {"table": "bikes", "column": "bike_id"},
        "bike number": {"table": "bikes", "column": "bike_id"},
        "bike_number": {"table": "bikes", "column": "bike_id"},
        "registration number": {"table": "bikes", "column": "bike_id"},
        "reg_number": {"table": "bikes", "column": "bike_id"},
        "reg no": {"table": "bikes", "column": "bike_id"},
        "vehicle number": {"table": "bikes", "column": "bike_id"},
        "model": {"table": "bikes", "column": "model"},
        "bike model": {"table": "bikes", "column": "model"},
        
        # ASSIGNMENTS TABLE
        "giving date": {"table": "bike_assignment", "column": "assigned_at"},
        "assigned_at": {"table": "bike_assignment", "column": "assigned_at"},
        "handover date": {"table": "bike_assignment", "column": "assigned_at"},
        "handover_date": {"table": "bike_assignment", "column": "assigned_at"},
        "handed over": {"table": "bike_assignment", "column": "assigned_at"},
        "given on": {"table": "bike_assignment", "column": "assigned_at"},
        "assignment date": {"table": "bike_assignment", "column": "assigned_at"},
        "assignment_date": {"table": "bike_assignment", "column": "assigned_at"},
        "start date": {"table": "bike_assignment", "column": "assigned_at"},
        "date out": {"table": "bike_assignment", "column": "assigned_at"},
        "collected by": {"table": "bike_assignment", "column": "assigned_at"},
        "delivery date": {"table": "bike_assignment", "column": "assigned_at"},
        "return date": {"table": "bike_assignment", "column": "returned_at"},
        "return_date": {"table": "bike_assignment", "column": "returned_at"},
        "returned_at": {"table": "bike_assignment", "column": "returned_at"},
        "returned_on": {"table": "bike_assignment", "column": "returned_at"},
        "returning date": {"table": "bike_assignment", "column": "returned_at"},
        "returning_date": {"table": "bike_assignment", "column": "returned_at"},
        "handed back": {"table": "bike_assignment", "column": "returned_at"},
        "end date": {"table": "bike_assignment", "column": "returned_at"},
        "end_date": {"table": "bike_assignment", "column": "returned_at"},
        "collected on": {"table": "bike_assignment", "column": "returned_at"},
        "date in": {"table": "bike_assignment", "column": "returned_at"},
        
        # ALIASES / PLATFORM
        "platform": {"table": "metadata", "column": "platform"},
        "project": {"table": "metadata", "column": "platform"},
        "company": {"table": "metadata", "column": "platform"},
        "work id": {"table": "rider_aliases", "column": "platform_rider_id"},
        "platform id": {"table": "rider_aliases", "column": "platform_rider_id"},
        "platform_id": {"table": "rider_aliases", "column": "platform_rider_id"},
        "talabat id": {"table": "rider_aliases", "column": "platform_rider_id", "platform_hint": "talabat"},
        "keeta id": {"table": "rider_aliases", "column": "platform_rider_id", "platform_hint": "keeta"},
        "courier id": {"table": "rider_aliases", "column": "platform_rider_id"},
        "partner id": {"table": "rider_aliases", "column": "platform_rider_id"},
        "rider id": {"table": "rider_aliases", "column": "platform_rider_id"},
        "staff id": {"table": "rider_aliases", "column": "platform_rider_id"},
        "staff_id": {"table": "rider_aliases", "column": "platform_rider_id"},
        "employee id": {"table": "rider_aliases", "column": "platform_rider_id"},
        "employee_id": {"table": "rider_aliases", "column": "platform_rider_id"},
        "internal id": {"table": "rider_aliases", "column": "platform_rider_id"},
        "system code": {"table": "rider_aliases", "column": "platform_rider_id"},
    }

    stats = {
        "riders": 0,
        "bikes": 0,
        "assignments": 0,
        "errors": []
    }

    recognized_headers = set()
    unrecognized_headers = set()

    def log_row_failure(row_no: int, reason: str):
        msg = f"Row {row_no}: {reason}"
        stats["errors"].append(msg)
        print(f"[UPLOAD][ERROR] {msg}")

    def log_row_info(row_no: int, info: str):
        print(f"[UPLOAD][INFO] Row {row_no}: {info}")

    from datetime import datetime, timedelta
    import dateutil.parser

    def robust_parse_date(val):
        if not val or str(val).strip().lower() in ('', 'null', 'none'):
            return None
        # Handle Excel serials
        if str(val).isdigit():
            try:
                days = int(val)
                # Excel 1900 bug handling
                origin = datetime(1899, 12, 30)
                return origin + timedelta(days=days)
            except: pass
        
        s = str(val).strip()

        # Strict ISO first to avoid day/month flip (example: 2024-03-10 -> 2024-10-03)
        if re.match(r'^\d{4}-\d{2}-\d{2}$', s):
            try:
                return datetime.strptime(s, "%Y-%m-%d")
            except:
                pass
        if re.match(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$', s):
            try:
                return datetime.fromisoformat(s.replace(' ', 'T'))
            except:
                pass

        try:
            # dayfirst for ambiguous non-ISO regional formats only
            return dateutil.parser.parse(s, dayfirst=True)
        except Exception:
            return None

    def normalize_rider_status(raw_status: str | None):
        if raw_status is None:
            return None
        value = str(raw_status).strip().lower().replace("_", " ")
        if not value:
            return None

        status_map = {
            "active": "active",
            "act": "active",
            "vacation": "vacation",
            "on vacation": "vacation",
            "retired": "retired",
            "inactive": "retired",
        }
        return status_map.get(value, value)

    def find_active_assignment(chassis_number: str | None):
        """
        Read active assignment using chassis_number only.
        Live DB schema for this project uses chassis_number as assignment key.
        """
        key_val = (chassis_number or "").strip()
        if not key_val:
            return []

        res = supabase.table("bike_assignment") \
            .select("*") \
            .eq("chassis_number", key_val) \
            .is_("returned_at", None) \
            .execute()
        return res.data or []

    def insert_assignment_compatible(base_payload: dict, chassis_number: str | None):
        """
        Insert assignment using chassis_number-only schema.
        """
        key_val = (chassis_number or "").strip()
        if not key_val:
            raise ValueError("Missing chassis_number for bike assignment insert")

        payload = dict(base_payload)
        payload["chassis_number"] = key_val
        supabase.table("bike_assignment").insert(payload).execute()

    def chunked(items, size=200):
        for i in range(0, len(items), size):
            yield items[i:i + size]

    row_contexts = []

    for idx, row in enumerate(rows):
        row_no = idx + 2  # +2 because Excel header is row 1
        try:
            rider_record = {}
            bike_record = {}
            assignment_start = None
            assignment_end = None
            platform = None
            work_ids = {}

            for header, value in row.items():
                if value is None or str(value).strip() == "":
                    continue
                clean_h = str(header).strip().lower()
                mapping = MAPPING.get(clean_h)
                if not mapping:
                    unrecognized_headers.add(clean_h)
                    continue
                recognized_headers.add(clean_h)

                table = mapping["table"]
                col = mapping["column"]
                val_str = str(value).strip()

                if table == "riders":
                    if col == "status":
                        rider_record[col] = normalize_rider_status(val_str)
                    elif col in {
                        "passport_expiry_date",
                        "emirates_id_expiry_date",
                        "visa_expiry_date",
                        "hold_until",
                    }:
                        dt = robust_parse_date(val_str)
                        rider_record[col] = dt.date().isoformat() if dt else None
                    else:
                        rider_record[col] = val_str
                elif table == "bikes":
                    bike_record[col] = val_str
                elif table == "bike_assignment":
                    dt = robust_parse_date(val_str)
                    if dt:
                        if col == "assigned_at":
                            assignment_start = dt
                        if col == "returned_at":
                            assignment_end = dt
                elif table == "metadata":
                    if col == "platform":
                        platform = val_str.lower()
                elif table == "rider_aliases":
                    hint = mapping.get("platform_hint")
                    if hint:
                        work_ids[hint] = val_str
                    else:
                        work_ids["pending"] = val_str

            eid = (rider_record.get("emirates_id_number") or "").strip()
            if not eid and not bike_record:
                log_row_failure(row_no, "Missing Emirates ID and no bike data found. Row skipped.")
                continue

            if not eid and bike_record:
                log_row_info(row_no, "Missing Emirates ID; rider was not upserted. Bike insert may proceed, assignment may be skipped.")

            row_contexts.append({
                "row_no": row_no,
                "rider_record": rider_record,
                "bike_record": bike_record,
                "assignment_start": assignment_start,
                "assignment_end": assignment_end,
                "platform": platform,
                "work_ids": work_ids,
                "eid": eid,
                "rider_uuid": None,
                "chassis": (bike_record.get("chassis_number") or "").strip(),
                "bike_ok": False,
            })
        except Exception as e:
            log_row_failure(row_no, f"Critical row failure: {str(e)}")

    # 2) Bulk rider upsert (last row wins per Emirates ID)
    riders_by_eid = {}
    for ctx in row_contexts:
        eid = ctx["eid"]
        if not eid:
            continue
        rec = dict(ctx["rider_record"])
        rec.setdefault("name", eid)
        rec.setdefault("status", "active")
        if user and isinstance(user, dict) and user.get("id"):
            rec["created_by_user_id"] = user["id"]
        riders_by_eid[eid] = rec

    import time
    from concurrent.futures import ThreadPoolExecutor, as_completed
    def parallel_batches(func, chunks, max_workers=4):
        results = []
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_chunk = {executor.submit(func, chunk): chunk for chunk in chunks}
            for future in as_completed(future_to_chunk):
                results.append(future.result())
        return results

    timing = {}
    start = time.time()
    if riders_by_eid:
        rider_records = list(riders_by_eid.values())
        def upsert_rider_batch(chunk):
            try:
                supabase.table("riders").upsert(chunk, on_conflict="emirates_id_number").execute()
                return None
            except Exception as e:
                for rec in chunk:
                    eid = rec.get("emirates_id_number")
                    related_rows = [c["row_no"] for c in row_contexts if c["eid"] == eid]
                    for row_no in related_rows:
                        log_row_failure(row_no, f"Rider upsert failed for EID {eid}. Raw error: {str(e)}")
                return str(e)
        rider_chunks = list(chunked(rider_records, 200))
        parallel_batches(upsert_rider_batch, rider_chunks)
        timing['rider_upsert'] = time.time() - start

        rider_id_by_eid = {}
        def fetch_rider_ids(eid_chunk):
            try:
                res = supabase.table("riders").select("id, emirates_id_number").in_("emirates_id_number", eid_chunk).execute()
                return [(str(r.get("emirates_id_number") or "").strip(), r.get("id")) for r in (res.data or [])]
            except Exception as e:
                print(f"[UPLOAD][WARN] Rider id prefetch failed for chunk: {e}")
                return []
        eid_chunks = list(chunked(list(riders_by_eid.keys()), 200))
        for result in parallel_batches(fetch_rider_ids, eid_chunks):
            for key, rid in result:
                if key and rid:
                    rider_id_by_eid[key] = rid
        timing['rider_id_fetch'] = time.time() - start - timing['rider_upsert']

        for ctx in row_contexts:
            if not ctx["eid"]:
                continue
            ctx["rider_uuid"] = rider_id_by_eid.get(ctx["eid"])
            if ctx["rider_uuid"]:
                stats["riders"] += 1
            else:
                log_row_failure(ctx["row_no"], f"Rider upsert returned no ID for EID {ctx['eid']}.")

    # 3) Bulk bike upsert by chassis
    bikes_by_chassis = {}
    bike_rows_by_chassis = {}
    for ctx in row_contexts:
        bike_record = ctx["bike_record"]
        if not bike_record:
            continue
        chassis = (bike_record.get("chassis_number") or "").strip()
        if not chassis:
            log_row_failure(ctx["row_no"], "Bike data exists but chassis_number is missing/unmapped, so bike insert skipped.")
            continue
        bikes_by_chassis[chassis] = bike_record
        bike_rows_by_chassis.setdefault(chassis, []).append(ctx["row_no"])

    bike_success_chassis = set()
    bike_start = time.time()
    if bikes_by_chassis:
        def upsert_bike_batch(chunk):
            try:
                supabase.table("bikes").upsert(chunk, on_conflict="chassis_number").execute()
                return [rec.get("chassis_number") for rec in chunk if rec.get("chassis_number")]
            except Exception as e:
                for rec in chunk:
                    ch = (rec.get("chassis_number") or "").strip()
                    if not ch:
                        continue
                    for row_no in bike_rows_by_chassis.get(ch, []):
                        bike_id_val = rec.get("bike_id")
                        if not bike_id_val:
                            log_row_failure(row_no, f"Bike insert failed. Missing mapped bike_id/plate value. Raw error: {str(e)}")
                        else:
                            log_row_failure(row_no, f"Bike insert failed for chassis {ch}. Raw error: {str(e)}")
                return []
        bike_chunks = list(chunked(list(bikes_by_chassis.values()), 200))
        results = parallel_batches(upsert_bike_batch, bike_chunks)
        for ch_list in results:
            bike_success_chassis.update(ch_list)
        timing['bike_upsert'] = time.time() - bike_start

    for ctx in row_contexts:
        if ctx["chassis"] and ctx["chassis"] in bike_success_chassis:
            ctx["bike_ok"] = True
            stats["bikes"] += 1

    # 4) Assignment handling with one active-assignment prefetch
    assignment_candidates = [
        c for c in row_contexts
        if c["rider_uuid"] and c["bike_ok"] and c["assignment_start"]
    ]

    active_by_chassis = {}
    assignment_chassis = sorted({c["chassis"] for c in assignment_candidates if c["chassis"]})
    for ch_chunk in chunked(assignment_chassis, 200):
        try:
            res = supabase.table("bike_assignment") \
                .select("*") \
                .in_("chassis_number", ch_chunk) \
                .is_("returned_at", None) \
                .execute()
            for rec in (res.data or []):
                ch = (rec.get("chassis_number") or "").strip()
                if ch and ch not in active_by_chassis:
                    active_by_chassis[ch] = rec
        except Exception as e:
            print(f"[UPLOAD][WARN] Active assignment prefetch failed for chunk: {e}")

    assignment_rows = []
    for ctx in sorted(assignment_candidates, key=lambda x: (x["assignment_start"], x["row_no"])):
        row_no = ctx["row_no"]
        chassis = ctx["chassis"]
        rider_uuid = ctx["rider_uuid"]
        assignment_start = ctx["assignment_start"]
        assignment_end = ctx["assignment_end"]
        existing = active_by_chassis.get(chassis)

        should_insert = True
        if existing:
            if existing.get("rider_id") == rider_uuid:
                should_insert = False
                log_row_info(row_no, f"Assignment already active for rider and chassis {chassis}; skipped duplicate assignment insert.")
            else:
                try:
                    ret_date = (assignment_start - timedelta(days=1)).isoformat()
                    start_str = existing.get("assigned_at")
                    if start_str:
                        old_start = dateutil.parser.parse(start_str).replace(tzinfo=None)
                        if old_start >= (assignment_start - timedelta(days=1)):
                            ret_date = old_start.isoformat()
                    supabase.table("bike_assignment").update({"returned_at": ret_date}).eq("id", existing["id"]).execute()
                    active_by_chassis.pop(chassis, None)
                except Exception as e:
                    should_insert = False
                    log_row_failure(row_no, f"Assignment close failed for chassis {chassis}. Raw error: {str(e)}")

        if should_insert:
            payload = {
                "rider_id": rider_uuid,
                "assigned_at": assignment_start.isoformat(),
                "rider_name": ctx["rider_record"].get("name", "Unknown"),
                "chassis_number": chassis,
            }
            if assignment_end:
                payload["returned_at"] = assignment_end.isoformat()
            assignment_rows.append((row_no, payload))
            active_by_chassis[chassis] = {
                "rider_id": rider_uuid,
                "assigned_at": payload["assigned_at"],
                "chassis_number": chassis,
            }

    assign_start = time.time()
    if assignment_rows:
        def insert_assignment_batch(chunk):
            payloads = [p for (_, p) in chunk]
            try:
                supabase.table("bike_assignment").insert(payloads).execute()
                return len(payloads)
            except Exception as e:
                for row_no, payload in chunk:
                    ch = payload.get("chassis_number")
                    log_row_failure(row_no, f"Assignment insert failed for chassis {ch}. Raw error: {str(e)}")
                return 0
        assign_chunks = list(chunked(assignment_rows, 200))
        results = parallel_batches(insert_assignment_batch, assign_chunks)
        stats["assignments"] += sum(results)
        timing['assignment_insert'] = time.time() - assign_start

    for ctx in row_contexts:
        if ctx["bike_record"] and not ctx["rider_uuid"]:
            log_row_info(ctx["row_no"], "Assignment skipped: rider UUID not available (likely missing/invalid Emirates ID).")
        if ctx["rider_uuid"] and ctx["bike_record"] and not ctx["bike_ok"]:
            log_row_info(ctx["row_no"], "Assignment skipped: chassis missing or bike insert failed.")
        if ctx["rider_uuid"] and ctx["bike_ok"] and not ctx["assignment_start"]:
            log_row_info(ctx["row_no"], "Assignment skipped: assigned_at date missing/unmapped/unparseable.")

    # 5) Bulk rider alias upsert
    aliases_by_key = {}
    for ctx in row_contexts:
        rider_uuid = ctx["rider_uuid"]
        if not rider_uuid:
            continue
        for p_name, p_id in ctx["work_ids"].items():
            target_p = ctx["platform"] if p_name == "pending" else p_name
            platform_id = (p_id or "").strip()
            platform_name = (target_p or "").strip().lower()
            if not platform_name or not platform_id:
                continue
            key = f"{platform_name}::{platform_id}"
            aliases_by_key[key] = {
                "rider_id": rider_uuid,
                "platform": platform_name,
                "platform_rider_id": platform_id,
            }

    alias_start = time.time()
    if aliases_by_key:
        def upsert_alias_batch(chunk):
            try:
                supabase.table("rider_aliases").upsert(chunk, on_conflict="platform,platform_rider_id").execute()
                return None
            except Exception as e:
                print(f"[UPLOAD][WARN] Alias upsert chunk failed: {e}")
                return str(e)
        alias_chunks = list(chunked(list(aliases_by_key.values()), 300))
        parallel_batches(upsert_alias_batch, alias_chunks)
        timing['alias_upsert'] = time.time() - alias_start

    processed = len(rows)
    inserted_total = stats['riders'] + stats['bikes'] + stats['assignments']
    failed_rows = len(stats["errors"])

    if inserted_total == 0 and processed > 0:
        return {
            "success": False,
            "message": "No records were inserted. Please check status/date/header values in your Excel file.",
            "processed_count": processed,
            "inserted_rows": 0,
            "failed_rows": failed_rows,
            "stats": stats,
            "recognized_headers": sorted(list(recognized_headers)),
            "unrecognized_headers": sorted(list(unrecognized_headers)),
        }

    partial_failure = failed_rows > 0
    if unrecognized_headers:
        print(f"[UPLOAD][INFO] Unrecognized headers: {sorted(list(unrecognized_headers))}")
    if recognized_headers:
        print(f"[UPLOAD][INFO] Recognized headers: {sorted(list(recognized_headers))}")

    timing['total'] = time.time() - start
    return {
        "success": True,
        "message": (
            f"Upload completed with warnings: {stats['riders']} riders, {stats['bikes']} bikes, and {stats['assignments']} assignments inserted."
            if partial_failure else
            f"Successfully processed {stats['riders']} riders, {stats['bikes']} bikes, and {stats['assignments']} assignments."
        ),
        "processed_count": processed,
        "inserted_rows": inserted_total,
        "failed_rows": failed_rows,
        "stats": stats,
        "timing": timing,
        "recognized_headers": sorted(list(recognized_headers)),
        "unrecognized_headers": sorted(list(unrecognized_headers)),
    }


@app.post("/riders")
def add_rider(
    rider: RiderCreate,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    try:
        data = {
            "name": rider.name,
            "emirates_id_number": rider.emirates_id_number,
            "phone": rider.phone,
            "city": rider.city,
            "status": rider.status,
            "passport_number": rider.passport_number,
            "wps_status": rider.wps_status,
            "release_hold": rider.release_hold,
            "created_by_user_id": rider.created_by_user_id,
            "passport_expiry_date": rider.passport_expiry_date,
            "emirates_id_expiry_date": rider.emirates_id_expiry_date,
            "visa_expiry_date": rider.visa_expiry_date,
            "hold_reason": rider.hold_reason,
            "hold_until": rider.hold_until,
        }

        res = supabase.table("riders").insert(data).execute()

        rider_id = res.data[0]["id"] if res.data and len(res.data) > 0 else None
        if not rider_id:
            raise HTTPException(status_code=400, detail="Failed to create rider")

        # Create action item for Accountant review
        action_item = {
            "type": "other",
            "title": rider.name,
            "subtitle": "New rider pending accountant review",
            "severity": "warning",
            "responsible_role": "accountant",
            "reference_id": rider_id,
            "created_at": datetime.utcnow().isoformat(),
        }
        supabase.table("action_items").insert(action_item).execute()

        return {
            "message": "Rider added successfully",
            "rider": res.data[0]
        }

    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to add rider: {e}"
        )


@app.get("/riders")
def list_riders(user = Depends(require_role(["ACCOUNTANT", "PRO"]))):
    try:
        # Keep rider fetch independent from relational embedding so endpoint does not
        # fail when PostgREST relation metadata differs across environments.
        res = supabase.table("riders") \
            .select("*") \
            .order("created_at", desc=True) \
            .execute()
        rows = res.data or []

        # Best-effort batch lookup for active bike assignments.
        assignment_by_rider = {}
        rider_uuid_ids = [r.get("id") for r in rows if r.get("id")]
        if rider_uuid_ids:
            try:
                assignment_res = supabase.table("bike_assignment") \
                    .select("rider_id, bike_id, assigned_at, returned_at") \
                    .in_("rider_id", rider_uuid_ids) \
                    .order("assigned_at", desc=True) \
                    .execute()
                for a in assignment_res.data or []:
                    rider_id = a.get("rider_id")
                    if not rider_id or rider_id in assignment_by_rider:
                        continue
                    if not a.get("returned_at"):
                        assignment_by_rider[rider_id] = {
                            "bike_id": a.get("bike_id"),
                            "assigned_at": a.get("assigned_at"),
                        }
            except Exception as assignment_error:
                print(f"Warning: bike assignment lookup failed in /riders: {assignment_error!r}")

        # Best-effort batch lookup for talabat/keeta aliases.
        alias_by_rider = {}
        if rider_uuid_ids:
            try:
                alias_res = supabase.table("rider_aliases") \
                    .select("rider_id, platform, platform_rider_id") \
                    .in_("rider_id", rider_uuid_ids) \
                    .execute()
                for a in alias_res.data or []:
                    rider_id = a.get("rider_id")
                    if not rider_id:
                        continue
                    if rider_id not in alias_by_rider:
                        alias_by_rider[rider_id] = {}
                    if a.get("platform") == "talabat":
                        alias_by_rider[rider_id]["talabat_id"] = a.get("platform_rider_id")
                    if a.get("platform") == "keeta":
                        alias_by_rider[rider_id]["keeta_id"] = a.get("platform_rider_id")
            except Exception as alias_error:
                print(f"Warning: rider aliases lookup failed in /riders: {alias_error!r}")

        riders = []
        for r in rows:
            active_assignment = assignment_by_rider.get(r.get("id"), {})
            active_bike = active_assignment.get("bike_id")
            assignment_date = active_assignment.get("assigned_at")
            
            # Add to rider dict (sanitized)
            rider_dict = {
                "rider_id": r.get("rider_id"),
                "id": r.get("rider_id", r.get("id")),
                "name": r.get("name"),
                "emirates_id_number": r.get("emirates_id_number"),
                "phone": r.get("phone"),
                "city": r.get("city"),
                "status": r.get("status"),
                "passport_expiry_date": r.get("passport_expiry_date"),
                "emirates_id_expiry_date": r.get("emirates_id_expiry_date"),
                "visa_expiry_date": r.get("visa_expiry_date"),
                "hold_reason": r.get("hold_reason"),
                "hold_until": r.get("hold_until"),
                "hold_set_by": r.get("hold_set_by"),
                "hold_set_at": r.get("hold_set_at"),
                # Populate platform alias IDs by querying rider_aliases
                # (avoid relying on deprecated rider table columns)
                "talabat_id": None,
                "keeta_id": None,
                "passport_number": r.get("passport_number"),
                "created_at": r.get("created_at"),
                "assigned_bike": active_bike or r.get("assigned_bike"),
                "assignment_date": assignment_date
            }
            alias_data = alias_by_rider.get(r.get("id"), {})
            rider_dict["talabat_id"] = alias_data.get("talabat_id")
            rider_dict["keeta_id"] = alias_data.get("keeta_id")
            riders.append(rider_dict)

        return {
            "riders": riders
        }
    except Exception as e:
        safe_msg = repr(e)
        print(f"Error fetching riders: {safe_msg}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to fetch riders: {safe_msg}"
        )


@app.get("/vendors")
def list_vendors(
    search: str | None = None,
    status: str | None = None,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    try:
        query = supabase.table("vendors").select("*").order("created_at", desc=True)
        if search:
            query = query.ilike("name", f"%{search.strip()}%")
        if status:
            query = query.eq("status", status.strip().lower())

        res = query.execute()
        return {"vendors": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch vendors: {e}")


@app.post("/vendors")
def create_vendor(
    payload: VendorCreate,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    try:
        status = payload.status.strip().lower()
        if status not in ["active", "inactive"]:
            raise HTTPException(status_code=400, detail="status must be active or inactive")

        data = {
            "name": payload.name.strip(),
            "phone": payload.phone,
            "email": payload.email,
            "address": payload.address,
            "vat_applicable": payload.vat_applicable,
            "vat_no": payload.vat_no,
            "status": status,
            "created_by_user_id": user["id"],
        }
        res = supabase.table("vendors").insert(data).execute()
        if not res.data:
            raise HTTPException(status_code=500, detail="Vendor creation failed")

        return {"message": "Vendor created successfully", "vendor": res.data[0]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to create vendor: {e}")


@app.get("/suppliers")
def list_suppliers(
    search: str | None = None,
    status: str | None = None,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    try:
        query = supabase.table("suppliers").select("*").order("created_at", desc=True)
        if search:
            query = query.ilike("name", f"%{search.strip()}%")
        if status:
            query = query.eq("status", status.strip().lower())

        res = query.execute()
        return {"suppliers": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch suppliers: {e}")


@app.post("/suppliers")
def create_supplier(
    payload: SupplierCreate,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    try:
        status = payload.status.strip().lower()
        if status not in ["active", "inactive"]:
            raise HTTPException(status_code=400, detail="status must be active or inactive")

        data = {
            "name": payload.name.strip(),
            "phone": payload.phone,
            "email": payload.email,
            "address": payload.address,
            "vat_applicable": False,
            "status": status,
            "created_by_user_id": user["id"],
        }
        res = supabase.table("suppliers").insert(data).execute()
        if not res.data:
            raise HTTPException(status_code=500, detail="Supplier creation failed")

        return {"message": "Supplier created successfully", "supplier": res.data[0]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to create supplier: {e}")


@app.post("/riders_with_action_item")
def add_rider_with_action_item(
    rider: RiderCreate,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    """Compatibility endpoint used by older app clients."""
    try:
        data = {
            "name": rider.name,
            "emirates_id_number": rider.emirates_id_number,
            "phone": rider.phone,
            "city": rider.city,
            "status": rider.status,
            "passport_number": rider.passport_number,
            "wps_status": rider.wps_status,
            "release_hold": rider.release_hold,
            "created_by_user_id": rider.created_by_user_id,
            "passport_expiry_date": rider.passport_expiry_date,
            "emirates_id_expiry_date": rider.emirates_id_expiry_date,
            "visa_expiry_date": rider.visa_expiry_date,
            "hold_reason": rider.hold_reason,
            "hold_until": rider.hold_until,
        }

        res = supabase.table("riders").insert(data).execute()
        rider_id = res.data[0]["id"] if res.data and len(res.data) > 0 else None
        if not rider_id:
            raise HTTPException(status_code=400, detail="Failed to create rider")

        supabase.table("action_items").insert({
            "type": "rider_pending_approval",
            "title": rider.name,
            "subtitle": "New rider pending accountant review",
            "severity": "warning",
            "responsible_role": "accountant",
            "reference_id": rider_id,
            "argument_id": rider_id,
            "route": "/accountant-dashboard/rider-approval",
            "created_at": datetime.utcnow().isoformat(),
        }).execute()

        return {
            "message": "Rider added successfully",
            "rider": res.data[0],
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to add rider with action item: {e}")


@app.post("/riders/approve")
def approve_rider_legacy(
    data: RiderApprovalRequest,
    user = Depends(require_role("ACCOUNTANT")),
):
    """Legacy approve endpoint retained for backward compatibility."""
    try:
        supabase.rpc("rpc_approve_rider_legacy", {"p_rider_id": data.rider_id}).execute()

        if data.action_item_id:
            supabase.table("action_items").update({
                "resolved_at": datetime.utcnow().isoformat(),
                "resolved_by": user["id"],
                "resolution_notes": "Approved from legacy endpoint",
            }).eq("id", data.action_item_id).execute()

        return {"message": "Rider approved"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to approve rider: {e}")


@app.post("/riders/reject")
def reject_rider_legacy(
    data: RiderRejectionRequest,
    user = Depends(require_role("ACCOUNTANT")),
):
    """Legacy reject endpoint retained for backward compatibility."""
    try:
        supabase.rpc(
            "rpc_reject_rider_legacy",
            {"p_rider_id": data.rider_id, "p_reason": data.reason},
        ).execute()

        if data.action_item_id:
            supabase.table("action_items").update({
                "resolved_at": datetime.utcnow().isoformat(),
                "resolved_by": user["id"],
                "resolution_notes": data.reason or "Rejected from legacy endpoint",
            }).eq("id", data.action_item_id).execute()

        return {"message": "Rider rejected"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to reject rider: {e}")


@app.get("/riders/{rider_id}/status-history")
def get_rider_status_history(
    rider_id: str,
    user = Depends(require_role(["ACCOUNTANT", "PRO"])),
):
    try:
        res = supabase.table("rider_status_history") \
            .select("*") \
            .eq("rider_id", rider_id) \
            .order("changed_at", desc=True) \
            .execute()
        return {"history": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch rider status history: {e}")


@app.post("/riders/{rider_id}/status")
def update_rider_status(
    rider_id: str,
    data: RiderStatusUpdateRequest,
    user = Depends(require_role("ACCOUNTANT")),
):
    try:
        payload = {
            "p_rider_id": rider_id,
            "p_new_status": data.status,
            "p_reason": data.reason,
            "p_effective_from": data.effective_from,
            "p_expected_return_date": data.expected_return_date,
        }
        supabase.rpc("rpc_update_rider_status", payload).execute()
        return {"message": "Rider status updated"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to update rider status: {e}")


@app.get("/riders/{rider_id}/hold-history")
def get_rider_hold_history(
    rider_id: str,
    user = Depends(require_role(["ACCOUNTANT", "PRO"])),
):
    try:
        res = supabase.table("rider_hold_history") \
            .select("*") \
            .eq("rider_id", rider_id) \
            .order("changed_at", desc=True) \
            .execute()
        return {"history": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch rider hold history: {e}")


@app.post("/riders/{rider_id}/release-hold")
def update_rider_release_hold(
    rider_id: str,
    data: RiderReleaseHoldRequest,
    user = Depends(require_role("ACCOUNTANT")),
):
    try:
        payload = {
            "p_rider_id": rider_id,
            "p_new_release_hold": data.release_hold,
            "p_reason": data.reason,
            "p_hold_until": data.hold_until,
        }
        supabase.rpc("rpc_set_rider_release_hold", payload).execute()
        return {"message": "Rider release/hold updated"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to update rider release/hold: {e}")


@app.get("/riders/{rider_id}/document-alerts")
def get_rider_document_alerts(
    rider_id: str,
    user = Depends(require_role(["ACCOUNTANT", "PRO"])),
):
    try:
        # Live expiry projection from view.
        expiry_res = supabase.table("v_rider_document_expiry") \
            .select("*") \
            .eq("rider_id", rider_id) \
            .order("days_to_expiry", desc=False) \
            .execute()

        # Persisted alert queue.
        alert_res = supabase.table("rider_document_alerts") \
            .select("*") \
            .eq("rider_id", rider_id) \
            .order("generated_at", desc=True) \
            .execute()

        return {
            "rider_id": rider_id,
            "live_expiry": expiry_res.data or [],
            "alerts": alert_res.data or [],
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch rider document alerts: {e}")


@app.post("/riders/{rider_id}/alias-conflicts/preview")
def preview_rider_alias_conflicts(
    rider_id: str,
    data: RiderAliasPreviewRequest,
    user = Depends(require_role("ACCOUNTANT")),
):
    try:
        payload = {
            "p_rider_id": rider_id,
            "p_platform": data.platform,
            "p_platform_rider_id": data.platform_rider_id,
            "p_valid_from": data.valid_from,
        }
        res = supabase.rpc("rpc_preview_rider_alias_conflicts", payload).execute()
        preview = res.data
        if isinstance(preview, list) and preview:
            preview = preview[0]
        return {"preview": preview or {}}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to preview alias conflicts: {e}")


@app.get("/drawer")
def get_drawer_summary(user = Depends(get_current_user)):
    try:
        # Step 1: Calculate balances from the ledger table
        # We assume Account mappings:
        # Bank -> CASH-BANK
        # Cash -> CASH-MAIN (petty_cash)
        # Noqodi -> CASH-NOQODI
        ledger_res = supabase.table("ledger") \
            .select("account_id, debit_amount, credit_amount") \
            .in_("account_id", ["CASH-BANK", "CASH-MAIN", "CASH-NOQODI"]) \
            .execute()
            
        bank_total = 0.0
        petty_cash_total = 0.0
        noqodi_total = 0.0

        for row in ledger_res.data or []:
            acc = row.get("account_id")
            debit = float(row.get("debit_amount") or 0)
            credit = float(row.get("credit_amount") or 0)
            # Cash accounts are Debit normal
            net_change = debit - credit
            
            if acc == "CASH-BANK":
                bank_total += net_change
            elif acc == "CASH-MAIN":
                petty_cash_total += net_change
            elif acc == "CASH-NOQODI":
                noqodi_total += net_change

        # PRO sees only noqodi + petty_cash, ACCOUNTANT sees all three
        if str(user.get("role", "")).lower() == "pro":
            return {
                "noqodi_cash": noqodi_total,
                "petty_cash_cash": petty_cash_total,
            }
        elif str(user.get("role", "")).lower() == "accountant":
            return {
                "noqodi_cash": noqodi_total,
                "petty_cash_cash": petty_cash_total,
                "bank_cash": bank_total,
            }
        else:
            raise HTTPException(status_code=403, detail="Forbidden")
    except Exception as e:
        # Log e in real app
        raise HTTPException(status_code=500, detail=f"Drawer summary error: {str(e)}")


@app.post("/drawer/topup")
def topup_drawer(
    data: DrawerTopupRequest,
    user = Depends(require_role(["ACCOUNTANT", "PRO"])),
):
    target = data.target_type.lower()
    amount = float(data.amount)

    if target not in ("noqodi", "petty_cash"):
        raise HTTPException(status_code=400, detail="Invalid target_type")

    if amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")

    try:
        # Get current balances directly from ledger
        ledger_res = supabase.table("ledger") \
            .select("account_id, debit_amount, credit_amount") \
            .in_("account_id", ["CASH-BANK", "CASH-MAIN", "CASH-NOQODI"]) \
            .execute()

        bank_total = 0.0
        noqodi_total = 0.0
        petty_cash_total = 0.0

        for row in ledger_res.data or []:
            acc = row.get("account_id")
            debit = float(row.get("debit_amount") or 0)
            credit = float(row.get("credit_amount") or 0)
            
            # Cash is a debit-normal account: Debit = Inflow, Credit = Outflow
            net = debit - credit
            
            if acc == "CASH-BANK":
                bank_total += net
            elif acc == "CASH-MAIN":
                petty_cash_total += net
            elif acc == "CASH-NOQODI":
                noqodi_total += net

        if bank_total < amount:
            raise HTTPException(status_code=400, detail=f"Insufficient bank balance. Current ledger derived balance: AED {bank_total:.2f}")

        # Topup is a transfer. We MUST create a balanced double entry Journal to represent it.
        # Credit CASH-BANK, Debit Target (CASH-MAIN or CASH-NOQODI)
        
        # Determine target account and drawer ids by querying drawer table (avoid hardcoded drawer ids)
        try:
            # Find target drawer row
            db_drawer_name = DRAWER_FRONTEND_TO_DB.get(target)
            if not db_drawer_name:
                raise HTTPException(status_code=400, detail="Invalid target drawer")

            target_drawer_res = supabase.table("drawer").select("id, name").eq("name", db_drawer_name).single().execute()
            bank_drawer_res = supabase.table("drawer").select("id, name").eq("name", DRAWER_FRONTEND_TO_DB.get('bank')).single().execute()

            if not target_drawer_res.data or not bank_drawer_res.data:
                raise HTTPException(status_code=404, detail="One or more drawers not found in DB")

            target_drawer_id = target_drawer_res.data['id']
            source_drawer_id = bank_drawer_res.data['id']

            # Map to ledger accounts
            target_account = "CASH-NOQODI" if db_drawer_name == "Noqodi" else "CASH-MAIN"

            # Create Journal
            journal_res = supabase.table("journals").insert({
                "date": datetime.now().isoformat(),
                "description": f"Internal Top-up from Bank to {db_drawer_name}",
                "status": "posted",
                "type": "General"
            }).execute()

            journal_id = journal_res.data[0]["id"]

            # Create Lines (only allowed columns for journal_lines)
            supabase.table("journal_lines").insert([
                {
                    "journal_id": journal_id,
                    "account_id": target_account,
                    "debit_amount": amount,
                    "credit_amount": 0,
                    "drawer_id": target_drawer_id
                },
                {
                    "journal_id": journal_id,
                    "account_id": "CASH-BANK",
                    "debit_amount": 0,
                    "credit_amount": amount,
                    "drawer_id": source_drawer_id
                }
            ]).execute()

            return {"message": "Topup successful (Journal Created)"}
        except HTTPException:
            raise
        except Exception as e:
            print(f"Topup internal error: {e}")
            raise HTTPException(status_code=400, detail="Failed to perform topup")

    except HTTPException:
        # Re-raise explicit HTTP errors
        raise
    except Exception:
        raise HTTPException(
            status_code=400,
            detail="Failed to perform topup"
        )


@app.post("/transactions")
def create_transaction(
    tx: TransactionCreate,
    user = Depends(require_role(["ACCOUNTANT", "PRO"])),
):
    from_drawer = tx.from_drawer.lower()
    reason = tx.reason
    rider_id = tx.rider_id

    db_drawer_name = DRAWER_FRONTEND_TO_DB.get(from_drawer)
    if not db_drawer_name:
        raise HTTPException(status_code=400, detail="Invalid from_drawer")

    # Map reasons to valid accounts
    allowed_reasons = ["government_legal", "loans_advances", "operational_expenses", "suspense_clearing"]
    if reason not in allowed_reasons:
        reason = "operational_expenses"

    # Do not substitute missing rider_id with hardcoded UUIDs. Allow nullable rider_id.
    if rider_id == "SYSTEM":
        rider_id = None

    try:
        # 1. Resolve drawer UUID and Account
        drawer_res = supabase.table("drawer").select("id").eq("name", db_drawer_name).single().execute()
        if not drawer_res.data:
            raise HTTPException(status_code=404, detail=f"Drawer '{db_drawer_name}' not found")

        drawer_id = drawer_res.data["id"]
        
        # Determine ledger account for this drawer
        drawer_account_id = "CASH-BANK"
        if db_drawer_name == "Cash": drawer_account_id = "CASH-MAIN"
        if db_drawer_name == "Noqodi": drawer_account_id = "CASH-NOQODI"
        
        # Calculate derived balance to ensure we have enough funds
        ledger_res = supabase.table("ledger").select("debit_amount, credit_amount").eq("account_id", drawer_account_id).execute()
        current_balance = sum((float(r.get("debit_amount") or 0) - float(r.get("credit_amount") or 0)) for r in (ledger_res.data or []))
        
        # Only check outbound (amount > 0 represents an expense based on the legacy UI logic being inverted or straight expense)
        # In current design, tx.amount for manual expense is passed as positive value, but represents an outbound drain.
        if tx.amount > 0 and current_balance < tx.amount:
              raise HTTPException(status_code=400, detail=f"Insufficient funds in {db_drawer_name}. Ledger balance: AED {current_balance:.2f}")

        # 2. Insert into the old Transactions table just to satisfy UI history panels (deprecated)
        tx_row = {
            "drawer_id": drawer_id,
            "rider_id": rider_id,
            "amount": tx.amount,
            "reason": reason,
            "status": "completed",
        }
        # Remove None values to avoid inserting explicit NULL for optional fields
        tx_row = {k: v for k, v in tx_row.items() if v is not None}
        res = supabase.table("transactions").insert(tx_row).execute()
        
        # 3. Create double-entry Journals explicitly
        journal_res = supabase.table("journals").insert({
            "date": datetime.now().isoformat(),
            "description": f"Manual Drawer Expense: {reason.replace('_', ' ').capitalize()}",
            "status": "posted",
            "type": "Expense"
        }).execute()
        
        journal_id = journal_res.data[0]["id"]
        
        # Expense account matching
        expense_acc_map = {
            "government_legal": "GOV-PRO-FEES",
            "loans_advances": "STAFF-ADVANCE",
            "operational_expenses": "GENERAL-EXPENSE",
            "suspense_clearing": "SUSPENSE-ACCOUNT"
        }
        
        target_expense_acc = expense_acc_map.get(reason, "GENERAL-EXPENSE")
        
        # Debit Expense, Credit Cash/Bank (only allowed columns)
        supabase.table("journal_lines").insert([
            {
                "journal_id": journal_id,
                "account_id": target_expense_acc,
                "debit_amount": tx.amount,
                "credit_amount": 0,
                "drawer_id": None
            },
            {
                "journal_id": journal_id,
                "account_id": drawer_account_id,
                "debit_amount": 0,
                "credit_amount": tx.amount,
                "drawer_id": drawer_id
            }
        ]).execute()

        return {
            "message": "Transaction booked directly into Ledger",
            "transaction": res.data[0],
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f"Transaction Error: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to create transaction: {str(e)}"
        )


@app.get("/transactions")
def list_transactions(
    status: str = "pending",
    user = Depends(require_role("ACCOUNTANT")),
):
    try:
        query = supabase.table("transactions") \
            .select("id, drawer_id, rider_id, amount, status, reason, created_at") \
            .order("created_at", desc=True)

        if status:
            query = query.eq("status", status)

        res = query.execute()

        return {
            "transactions": res.data or []
        }
    except Exception:
        raise HTTPException(
            status_code=400,
            detail="Failed to fetch transactions"
        )


@app.post("/transactions/{transaction_id}/approve")
def approve_transaction(
    transaction_id: str,
    user = Depends(require_role("ACCOUNTANT")),
):
    try:
        tx_res = supabase.table("transactions") \
            .select("*") \
            .eq("id", transaction_id) \
            .single() \
            .execute()

        tx = tx_res.data

        if not tx:
            raise HTTPException(status_code=404, detail="Transaction not found")

        if tx["status"] != "pending":
            raise HTTPException(status_code=400, detail="Transaction is not pending")

        drawer_id = tx.get("drawer_id")
        amount = float(tx.get("amount") or 0)
        reason = tx.get("reason", "operational_expenses")
        rider_id = tx.get("rider_id")

        if not drawer_id:
            raise HTTPException(status_code=400, detail="Transaction has no drawer_id")

        # Get the drawer name
        drawer_res = supabase.table("drawer").select("name").eq("id", drawer_id).single().execute()
        if not drawer_res.data:
            raise HTTPException(status_code=404, detail="Drawer not found")
            
        db_drawer_name = drawer_res.data["name"]
        
        # Determine ledger account for this drawer
        drawer_account_id = "CASH-BANK"
        if db_drawer_name == "Cash": drawer_account_id = "CASH-MAIN"
        if db_drawer_name == "Noqodi": drawer_account_id = "CASH-NOQODI"
        
        # Calculate derived balance strictly from Ledger
        ledger_res = supabase.table("ledger").select("debit_amount, credit_amount").eq("account_id", drawer_account_id).execute()
        current_balance = sum((float(r.get("debit_amount") or 0) - float(r.get("credit_amount") or 0)) for r in (ledger_res.data or []))

        if amount > 0 and current_balance < amount:
            raise HTTPException(
                status_code=400,
                detail=f"Insufficient balance in drawer '{db_drawer_name}'. Ledger balance: AED {current_balance:.2f}"
            )

        # Mark legacy transaction as approved
        supabase.table("transactions").update({"status": "approved"}).eq("id", transaction_id).execute()
        
        # Create double-entry Journals explicitly
        journal_res = supabase.table("journals").insert({
            "date": datetime.now().isoformat(),
            "description": f"Approved Manual Drawer Expense: {reason.replace('_', ' ').capitalize()}",
            "status": "posted",
            "type": "Expense"
        }).execute()
        
        journal_id = journal_res.data[0]["id"]
        
        expense_acc_map = {
            "government_legal": "GOV-PRO-FEES",
            "loans_advances": "STAFF-ADVANCE",
            "operational_expenses": "GENERAL-EXPENSE",
            "suspense_clearing": "SUSPENSE-ACCOUNT"
        }
        
        target_expense_acc = expense_acc_map.get(reason, "GENERAL-EXPENSE")
        
        # Debit target expense, Credit source drawer (only allowed columns)
        supabase.table("journal_lines").insert([
            {
                "journal_id": journal_id,
                "account_id": target_expense_acc,
                "debit_amount": amount,
                "credit_amount": 0,
                "drawer_id": None
            },
            {
                "journal_id": journal_id,
                "account_id": drawer_account_id,
                "debit_amount": 0,
                "credit_amount": amount,
                "drawer_id": drawer_id
            }
        ]).execute()

        return {"message": "Transaction approved and booked to Ledger"}

    except HTTPException:
        raise
    except Exception as e:
        print(f"Approval Error: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to approve transaction: {str(e)}"
        )


@app.post("/transactions/{transaction_id}/reject")
def reject_transaction(
    transaction_id: str,
    user = Depends(require_role("ACCOUNTANT")),
):
    try:
        tx_res = supabase.table("transactions") \
            .select("*") \
            .eq("id", transaction_id) \
            .single() \
            .execute()

        tx = tx_res.data

        if not tx:
            raise HTTPException(status_code=404, detail="Transaction not found")

        if tx["status"] != "pending":
            raise HTTPException(status_code=400, detail="Transaction is not pending")

        supabase.table("transactions").update({"status": "rejected"}) \
            .eq("id", transaction_id) \
            .execute()

        return {"message": "Transaction rejected"}

    except HTTPException:
        raise
    except Exception:
        raise HTTPException(
            status_code=400,
            detail="Failed to reject transaction"
        )


# Bikes CRUD endpoints (ACCOUNTANT only)
@app.post("/bikes")
def create_bike(
    bike: BikeCreate,
    user = Depends(require_role("ACCOUNTANT")),
):
    try:
        row = {"bike_id": bike.bike_id}
        if bike.model:
            row["model"] = bike.model
        res = supabase.table("bikes").insert(row).execute()

        return {
            "message": "Bike created successfully",
            "bike": res.data[0]
        }
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to create bike: {str(e)}"
        )


@app.get("/bikes")
def list_bikes(user = Depends(require_role("ACCOUNTANT"))):
    try:
        res = supabase.table("bikes") \
            .select("bike_id, model, salik_id, status, created_at") \
            .order("created_at", desc=True) \
            .execute()

        return {
            "bikes": res.data or []
        }
    except Exception:
        raise HTTPException(
            status_code=400,
            detail="Failed to fetch bikes"
        )


@app.delete("/bikes/{bike_id}")
def delete_bike(
    bike_id: str,
    user = Depends(require_role("ACCOUNTANT")),
):
    try:
        res = supabase.table("bikes") \
            .delete() \
            .eq("bike_id", bike_id) \
            .execute()

        if not res.data:
            raise HTTPException(status_code=404, detail="Bike not found")

        return {"message": "Bike deleted successfully"}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(
            status_code=400,
            detail="Failed to delete bike"
        )


@app.post("/riders/{rider_id}/assign-keeta")
def assign_keeta(
    rider_id: str,
    data: PlatformIdRequest,
    user = Depends(require_role("ACCOUNTANT"))
):
    try:
        # Instead of writing platform ids into riders table, upsert into rider_aliases
        alias = {
            "rider_id": rider_id,
            "platform": "keeta",
            "platform_rider_id": data.platform_id
        }
        supabase.table("rider_aliases").upsert(alias, on_conflict="platform,rider_id").execute()
        return {"message": "Keeta alias assigned successfully", "keeta_id": data.platform_id}
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to assign Keeta ID: {str(e)}"
        )


@app.post("/riders/{rider_id}/assign-talabat")
def assign_talabat(
    rider_id: str,
    data: PlatformIdRequest,
    user = Depends(require_role("ACCOUNTANT"))
):
    try:
        alias = {
            "rider_id": rider_id,
            "platform": "talabat",
            "platform_rider_id": data.platform_id
        }
        supabase.table("rider_aliases").upsert(alias, on_conflict="platform,rider_id").execute()
        return {"message": "Talabat alias assigned successfully", "talabat_id": data.platform_id}
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to assign Talabat ID: {str(e)}"
        )



@app.get("/bike-assignments")
def list_bike_assignments(user = Depends(require_role(["ACCOUNTANT", "PRO"]))):
    try:
        # Service Key bypasses RLS
        # Fetch assignments and join with riders table to get name
        res = supabase.table("bike_assignment") \
            .select("*, riders(name)") \
            .order("assigned_at", desc=True) \
            .execute()
        
        assignments = []
        for item in res.data or []:
            # Flatten rider name
            rider_data = item.get("riders")
            rider_name = rider_data.get("name") if rider_data else "Unknown"
            
            # Add to item
            item["rider_name"] = rider_name
            assignments.append(item)
            
        return {
            "assignments": assignments
        }
    except Exception as e:
        print(f"Error fetching assignments: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to fetch assignments: {str(e)}"
        )

class BikeChassisAssignmentRequest(BaseModel):
    chassis_number: str


@app.post("/riders/{rider_id}/assign-bike")
def assign_bike_to_rider(
    rider_id: str,
    data: BikeChassisAssignmentRequest,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    try:
        chassis = data.chassis_number.strip()
        if not chassis:
             raise HTTPException(status_code=400, detail="Chassis number cannot be empty")

        # 1. Check if rider ALREADY has another bike assigned (NEW SAFETY CHECK)
        rider_block_res = supabase.table("bike_assignment") \
            .select("id") \
            .eq("rider_id", rider_id) \
            .is_("returned_at", "null") \
            .execute()
        
        if rider_block_res.data:
            raise HTTPException(status_code=400, detail="Rider already has an active bike assignment.")

        # 2. Check if bike exists
        bike_res = supabase.table("bikes").select("*").eq("chassis_number", chassis).execute()
        
        if not bike_res.data:
            # Create new entry if missing (fallback)
            supabase.table("bikes").insert({
                "chassis_number": chassis,
                "bike_id": f"PENDING-{chassis[:6]}", # Temp Plate
                "status": "active"
            }).execute()
        
        # 3. Assign to Rider
        # Close any previous active assignment for THIS chassis if it exists elsewhere
        supabase.table("bike_assignment") \
            .update({"returned_at": datetime.now().isoformat()}) \
            .eq("chassis_number", chassis) \
            .is_("returned_at", "null") \
            .execute()

        supabase.table("bike_assignment").insert({
            "rider_id": rider_id,
            "chassis_number": chassis,
            "assigned_at": datetime.now().isoformat()
        }).execute()
        
        return {"message": "Bike assigned successfully"}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to assign bike: {str(e)}"
        )


@app.post("/bikes/assign")
def assign_bike(
    data: BikeAssignmentCreate,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    try:
        # 1. Check if rider already has an active assignment
        rider_check = supabase.table("bike_assignment") \
            .select("id") \
            .eq("rider_id", data.rider_id) \
            .is_("returned_at", "null") \
            .execute()
        
        if rider_check.data:
            raise HTTPException(status_code=400, detail="Rider already has an active bike assignment")

        # 2. Check if bike exists and status
        bike_res = supabase.table("bikes") \
            .select("status") \
            .eq("chassis_number", data.chassis_number) \
            .single() \
            .execute()
        
        if not bike_res.data:
            raise HTTPException(status_code=404, detail="Bike not found")
        
        if bike_res.data["status"] != "active":
            raise HTTPException(
                status_code=400, 
                detail=f"Bike cannot be assigned because its status is '{bike_res.data['status']}'"
            )

        # 3. Check if bike is already assigned to someone else
        bike_assignment_check = supabase.table("bike_assignment") \
            .select("id") \
            .eq("chassis_number", data.chassis_number) \
            .is_("returned_at", "null") \
            .execute()
        
        if bike_assignment_check.data:
            raise HTTPException(status_code=400, detail="Bike is already assigned (Chassis: {data.chassis_number})")

        # 4. Create assignment record
        supabase.table("bike_assignment").insert({
            "rider_id": data.rider_id,
            "chassis_number": data.chassis_number,
            "assigned_at": datetime.now().isoformat()
        }).execute()

        return {"message": "Bike assigned successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Assignment failed: {str(e)}")


@app.post("/bikes/{chassis_number}/return")
def return_bike(
    chassis_number: str,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    try:
        # Update current assignment (where returned_at is null)
        res = supabase.table("bike_assignment") \
            .update({"returned_at": datetime.now().isoformat()}) \
            .eq("chassis_number", chassis_number) \
            .is_("returned_at", "null") \
            .execute()

        if not res.data:
             raise HTTPException(status_code=400, detail="No active assignment found for this bike")
             
        return {"message": "Bike returned successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Return failed: {str(e)}")


# --- Traffic Fines Module ---

def find_rider_by_name(rider_name: str):
    """Look up a rider in the database by name (case-insensitive).
    Returns the rider's UUID if exactly one match is found, None otherwise."""
    if not rider_name or not rider_name.strip():
        return None
    try:
        clean_name = rider_name.strip()
        # Case-insensitive search using ilike
        res = supabase.table("riders") \
            .select("id, name") \
            .ilike("name", clean_name) \
            .execute()
        
        matches = res.data or []
        
        if len(matches) == 1:
            print(f"Name match found: '{clean_name}' -> rider ID {matches[0]['id']}")
            return matches[0]["id"]
        elif len(matches) > 1:
            # Try exact match (case-insensitive) to narrow down
            exact = [m for m in matches if m["name"].strip().lower() == clean_name.lower()]
            if len(exact) == 1:
                print(f"Exact name match found: '{clean_name}' -> rider ID {exact[0]['id']}")
                return exact[0]["id"]
            print(f"Multiple riders found for name '{clean_name}': {[m['name'] for m in matches]}. Skipping auto-match.")
            return None
        else:
            print(f"No rider found with name '{clean_name}'")
            return None
    except Exception as e:
        print(f"Error in find_rider_by_name: {e}")
        return None


def find_rider_for_fine(plate_number: str, violation_datetime: datetime, rider_name: str = None):
    try:
        # 1. Resolve Chassis from Plate (Fines only have Plate)
        bike_res = supabase.table("bikes").select("chassis_number").eq("bike_id", plate_number).execute()
        if not bike_res.data:
            print(f"No bike found for plate {plate_number}")
            # Try name match fallback immediately
            if rider_name:
                 return find_rider_by_name(rider_name)
            return None
        
        chassis = bike_res.data[0]["chassis_number"]

        # 2. Check bike_assignment table for date-range match using CHASSIS
        res = supabase.table("bike_assignment") \
            .select("*") \
            .eq("chassis_number", chassis) \
            .execute()
        
        assignments = res.data or []
        
        for assignment in assignments:
            start_str = assignment.get("assigned_at")
            end_str = assignment.get("returned_at")
            
            if not start_str:
                continue
                
            start_dt = datetime.fromisoformat(start_str.replace('Z', '+00:00')).replace(tzinfo=None)
            
            if end_str:
                end_dt = datetime.fromisoformat(end_str.replace('Z', '+00:00')).replace(tzinfo=None)
                if start_dt <= violation_datetime <= end_dt:
                    print(f"Chassis date-range match: '{chassis}' -> rider {assignment.get('rider_id')}")
                    return assignment.get("rider_id")
            else:
                if violation_datetime >= start_dt:
                    print(f"Chassis active-assignment match: '{chassis}' -> rider {assignment.get('rider_id')}")
                    return assignment.get("rider_id")
        
        # 3. Fallback - check for ANY active assignment for this chassis
        active_assignments = [a for a in assignments if not a.get("returned_at")]
        if len(active_assignments) == 1:
            rider_id = active_assignments[0].get("rider_id")
            print(f"Chassis active-fallback match: '{chassis}' -> rider {rider_id}")
            return rider_id
        
        # 4. Fallback - try matching by rider name from Excel
        if rider_name:
            print(f"Chassis match failed for '{chassis}'. Trying name-based match with '{rider_name}'...")
            return find_rider_by_name(rider_name)
                    
        return None
    except Exception as e:
        print(f"Error in find_rider_for_fine: {e}")
        return None


@app.post("/fines/upload-single")
def upload_single_fine(
    fine: FineCreate,
    user = Depends(require_role("ACCOUNTANT"))
):
    try:
        # 1. Parse DateTime
        # Input format: YYYY-MM-DD and HH:MM
        violation_dt = datetime.strptime(f"{fine.violation_date} {fine.violation_time}", "%Y-%m-%d %H:%M")
        
        # 2. Find Rider (plate-based first, then name-based fallback)
        rider_id = find_rider_for_fine(fine.plate_number, violation_dt, rider_name=fine.rider_name)
        
        status = "matched" if rider_id else "unmatched"
        
        # 3. Create Fine Record
        fine_data = {
            "ticket_number": fine.ticket_number,
            "plate_number": fine.plate_number,
            "violation_date": violation_dt.isoformat(),
            "amount": fine.amount,
            "description": fine.description,
            "city": fine.city,
            "rider_id": rider_id,
            "rider_name": fine.rider_name,
            "status": status 
            # Do NOT add expense_type for fines
        }
        
        res = supabase.table("traffic_fines").insert(fine_data).execute()

        # --- Create recoverable journal for this fine (always recoverable, type: fine) ---
        try:
            if rider_id:
                journal_data = {
                    "type": "fine",
                    "base_amount": fine.amount,
                    "total_amount": fine.amount,
                    "is_receivable": True,
                    "receivable_amount": fine.amount,
                    "status": "posted",
                    "rider_id": rider_id,
                    "description": f"Traffic Fine: {fine.description}",
                    "category": "traffic_fine",
                    "party_type": "rider",
                    "receivable_entity_type": "rider",
                }
                supabase.table("journals").insert(journal_data).execute()
        except Exception as je:
            print(f"Warning: Failed to create recoverable journal for fine: {je}")

        return {
            "message": "Fine uploaded successfully",
            "fine": res.data[0],
            "matched_rider": rider_id is not None,
            "status": status
        }

    except Exception as e:
        print(f"Error uploading fine: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to upload fine: {str(e)}"
        )


@app.post("/fines/upload-bulk")
def upload_bulk_fines(
    request: FineBulkUploadRequest,
    user = Depends(require_role("ACCOUNTANT"))
):
    results = {
        "total": len(request.fines),
        "matched": 0,
        "unmatched": 0,
        "errors": 0
    }
    
    upload_data = []
    
    for fine in request.fines:
        try:
            # 1. Parse DateTime
            violation_dt = datetime.strptime(f"{fine.violation_date} {fine.violation_time}", "%Y-%m-%d %H:%M")
            
            # 2. Find Rider (plate-based first, then name-based fallback)
            rider_id = find_rider_for_fine(fine.plate_number, violation_dt, rider_name=fine.rider_name)
            
            status = "matched" if rider_id else "unmatched"
            if rider_id:
                results["matched"] += 1
            else:
                results["unmatched"] += 1
                
            # 3. Prepare Fine Record
            upload_data.append({
                "ticket_number": fine.ticket_number,
                "plate_number": fine.plate_number,
                "violation_date": violation_dt.isoformat(),
                "amount": fine.amount,
                "description": fine.description,
                "city": fine.city,
                "rider_id": rider_id,
                "rider_name": fine.rider_name,
                "status": status 
                # Do NOT add expense_type for fines
            })
            # --- Create recoverable journal for this fine (always recoverable, type: fine) ---
            try:
                if rider_id:
                    journal_data = {
                        "type": "fine",
                        "base_amount": fine.amount,
                        "total_amount": fine.amount,
                        "is_receivable": True,
                        "receivable_amount": fine.amount,
                        "status": "posted",
                        "rider_id": rider_id,
                        "description": f"Traffic Fine: {fine.description}",
                        "category": "traffic_fine",
                        "party_type": "rider",
                        "receivable_entity_type": "rider",
                    }
                    supabase.table("journals").insert(journal_data).execute()
            except Exception as je:
                print(f"Warning: Failed to create recoverable journal for fine: {je}")
        except Exception as e:
            print(f"Error preparing bulk fine: {e}")
            results["errors"] += 1
            
    if upload_data:
        try:
            supabase.table("traffic_fines").insert(upload_data).execute()
        except Exception as e:
            print(f"Error inserting bulk fines: {e}")
            raise HTTPException(
                status_code=400,
                detail=f"Failed to upload bulk fines: {str(e)}"
            )
            
    return {
        "message": f"Bulk upload completed: {results['matched']} matched, {results['unmatched']} unmatched",
        "summary": results
    }


@app.get("/fines")
def list_fines():
    try:
        # Join with riders to get name. 
        res = supabase.table("traffic_fines") \
            .select("*, riders(name)") \
            .order("violation_date", desc=True) \
            .execute()
            
        fines = []
        rider_name_cache: dict[str, str] = {}
        for item in res.data or []:
            # Flatten rider name
            rider_data = item.get("riders")
            rider_name = rider_data.get("name") if rider_data else item.get("rider_name")

            # For unmatched rows, try DB fallback using assignment history.
            # This is response-only enrichment so existing status/workflow remain unchanged.
            if (not rider_name) and str(item.get("status") or "").lower() == "unmatched":
                try:
                    plate_number = str(item.get("plate_number") or "").strip()
                    violation_raw = item.get("violation_date")
                    if plate_number and violation_raw:
                        violation_dt = datetime.fromisoformat(str(violation_raw).replace("Z", "+00:00"))
                        inferred_rider_id = find_rider_for_fine(plate_number, violation_dt)
                        if inferred_rider_id:
                            if inferred_rider_id in rider_name_cache:
                                rider_name = rider_name_cache[inferred_rider_id]
                            else:
                                rr = supabase.table("riders") \
                                    .select("name") \
                                    .eq("id", inferred_rider_id) \
                                    .maybe_single() \
                                    .execute()
                                inferred_name = (rr.data or {}).get("name") if rr.data else None
                                if inferred_name:
                                    rider_name_cache[inferred_rider_id] = inferred_name
                                    rider_name = inferred_name
                except Exception:
                    # Keep existing response behavior if fallback inference fails.
                    pass
            
            item["rider_name"] = rider_name
            fines.append(item)
            
        return fines
    except Exception as e:
        print(f"Error fetching fines: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to fetch fines: {str(e)}"
        )


@app.put("/fines/{fine_id}/assign")
def assign_fine_manual(
    fine_id: str,
    data: FineAssignRequest
):
    try:
        # Update record and set status to matched
        res = supabase.table("traffic_fines").update({
            "rider_id": data.rider_id,
            "status": "matched"
        }).eq("id", fine_id).execute()
        
        if not res.data:
            raise HTTPException(status_code=404, detail="Fine not found")
            
        return {"message": "Fine assigned successfully", "fine": res.data[0]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/fines/{fine_id}/assignment-proof")
def get_fine_assignment_proof(fine_id: str):
    try:
        # 1. Get Fine Info
        fine_res = supabase.table("traffic_fines").select("*").eq("id", fine_id).single().execute()
        fine = fine_res.data
        if not fine:
            raise HTTPException(status_code=404, detail="Fine not found")
            
        plate = fine["plate_number"]
        violation_dt = datetime.fromisoformat(fine["violation_date"].replace('Z', '+00:00')).replace(tzinfo=None)
        
        # 2. Find Assignment
        res = supabase.table("bike_assignment") \
            .select("*, riders(name)") \
            .eq("bike_id", plate) \
            .execute()
            
        assignments = res.data or []
        for assignment in assignments:
            start_str = assignment.get("assigned_at")
            end_str = assignment.get("returned_at")
            
            if not start_str: continue
            
            start_dt = datetime.fromisoformat(start_str.replace('Z', '+00:00')).replace(tzinfo=None)
            
            if end_str:
                end_dt = datetime.fromisoformat(end_str.replace('Z', '+00:00')).replace(tzinfo=None)
                if start_dt <= violation_dt <= end_dt:
                    return assignment
            else:
                if violation_dt >= start_dt:
                    return assignment
                    
        raise HTTPException(status_code=404, detail="No matching assignment found for this timeframe")
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=400, detail=str(e))


@app.put("/fines/bulk-status")
def bulk_update_fine_status(
    data: BulkStatusRequest,
    user = Depends(require_role("ACCOUNTANT"))
):
    try:
        if not data.ids:
            return {"message": "No IDs provided"}
            
        res = supabase.table("traffic_fines") \
            .update({"status": data.status}) \
            .in_("id", data.ids) \
            .execute()
            
        return {"message": f"Successfully updated {len(res.data)} fines to {data.status}"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# --- Expenses Module ---

@app.post("/expenses")
def create_expense(
    expense: ExpenseCreate,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    """
    Atomic expense creation (PRO flow):
    1. Create a draft journal
    2. Create the expense row linked to that journal
    3. Create an action_item in the DB for the accountant
    4. Write audit_log entries
    """
    try:
        if expense.amount <= 0:
             raise HTTPException(status_code=400, detail="Amount must be positive")

        # Look up rider name for denormalization
        rider_name = None
        try:
            rider_res = supabase.table("riders").select("name").eq("id", expense.rider_id).single().execute()
            if rider_res.data:
                rider_name = rider_res.data["name"]
        except Exception:
            pass

        # Look up category default_type if category_id provided
        journal_type = "expense"
        if expense.category_id:
            try:
                cat_res = supabase.table("expense_categories").select("default_type").eq("id", expense.category_id).single().execute()
                if cat_res.data:
                    journal_type = cat_res.data["default_type"]
            except Exception:
                pass

        # Step 1: Create draft journal
        journal_id = str(uuid.uuid4())
        journal_description = (expense.description or '').strip()
        if not journal_description:
            journal_description = expense.expense_type
        journal_data = {
            "id": journal_id,
            "entry_date": expense.expense_date,
            "description": journal_description,
            "total_amount": expense.amount,
            "base_amount": expense.amount,
            "vat_rate": 0,
            "vat_amount": 0,
            "status": "draft",
            "type": journal_type,
            "created_by_user_id": user["id"],
            "created_by_role": "pro",
            "is_receivable": False,  # PRO does not decide this
            # No drawer_id — PRO does not know which drawer
            # No payment_method — accountant will set
            "receipt_url": expense.receipt_url,
        }
        supabase.table("journals").insert(journal_data).execute()

        # Step 2: Create expense row linked to journal
        expense_data = {
            "rider_id": expense.rider_id,
            "rider_name": rider_name,
            "expense_type": expense.expense_type,
            "amount": expense.amount,
            "base_amount": expense.amount,
            "vat_rate": 0,
            "vat_amount": 0,
            "expense_date": expense.expense_date,
            "description": expense.description,
            "status": "pending",
            "journal_id": journal_id,
            "created_by_role": user["role"],
            "receipt_url": expense.receipt_url,
        }
        if expense.category_id:
            expense_data["category_id"] = expense.category_id

        expense_res = supabase.table("expenses").insert(expense_data).execute()
        expense_row = expense_res.data[0] if expense_res.data else None

        # Step 3: Create action_item in DB for accountant
        action_item_data = {
            "type": "journal_pending_approval",
            "title": f"Pending Expense: {expense.expense_type}",
            "subtitle": f"AED {expense.amount} • {rider_name or 'Unknown Rider'}",
            "severity": "warning",
            "route": "/journals",
            "argument_id": journal_id,
            "related_entity": "journal",
            "reference_id": journal_id,
            "responsible_role": "accountant",
        }
        supabase.table("action_items").insert(action_item_data).execute()

        # Step 4: Write audit_log entries
        write_audit_log(
            table_name="journals",
            record_id=journal_id,
            action="INSERT",
            new_data=journal_data,
            user_id=user["id"],
        )
        if expense_row:
            write_audit_log(
                table_name="expenses",
                record_id=expense_row["id"],
                action="INSERT",
                new_data=expense_data,
                user_id=user["id"],
            )

        return {
            "message": "Expense created successfully",
            "expense": expense_row,
            "journal_id": journal_id,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to create expense: {str(e)}"
        )


@app.get("/expenses")
def list_expenses(
    created_by_role: str | None = None,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    try:
        # Join with riders to get name
        query = supabase.table("expenses").select("*, riders(name)").order("expense_date", desc=True)
        
        if created_by_role and created_by_role != "All":
             query = query.eq("created_by_role", created_by_role)
             
        res = query.execute()
            
        expenses = []
        for item in res.data or []:
            # Flatten rider name
            rider_data = item.get("riders")
            rider_name = rider_data.get("name") if rider_data else "Unknown"
            
            item["rider_name"] = rider_name
            expenses.append(item)
            
        return {"expenses": expenses}
        
    except Exception as e:
        print(f"Error fetching expenses: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to fetch expenses: {str(e)}"
        )


@app.delete("/expenses/{expense_id}")
def delete_expense(
    expense_id: str,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    try:
        res = supabase.table("expenses") \
            .delete() \
            .eq("id", expense_id) \
            .execute()
            
        if not res.data:
            raise HTTPException(status_code=404, detail="Expense not found")
            
        return {"message": "Expense deleted successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to delete expense: {str(e)}"
        )


@app.put("/expenses/{expense_id}/status")
def update_expense_status(
    expense_id: str,
    status_update: ExpenseStatusUpdate,
    user = Depends(require_role("ACCOUNTANT"))
):
    try:
        new_status = status_update.status
        if new_status not in ["approved", "rejected", "pending"]:
             raise HTTPException(status_code=400, detail="Invalid status")

        # Normalize to lowercase
        new_status = new_status.lower()

        res = supabase.table("expenses") \
            .update({"status": new_status}) \
            .eq("id", expense_id) \
            .execute()
            
        if not res.data:
            raise HTTPException(status_code=404, detail="Expense not found")
            
        return {
            "message": "Expense status updated successfully",
            "expense": res.data[0]
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to update expense status: {str(e)}"
        )


# --- Journals Module ---

class JournalLineCreate(BaseModel):
    account_id: str
    debit_amount: float = 0
    credit_amount: float = 0
    drawer_id: str | None = None

class JournalCreate(BaseModel):
    entry_date: str  # YYYY-MM-DD
    description: str
    status: str = "draft"
    type: str | None = None  # journal_type enum: expense, salary, fine, loan, manual_adjustment
    created_by_role: str | None = None  # user_role enum
    total_amount: float | None = None
    base_amount: float | None = None
    vat_rate: float | None = None
    vat_amount: float | None = None
    payment_method: str | None = None
    drawer_id: str | None = None
    is_receivable: bool = False
    is_payable: bool = False
    receivable_entity_type: str | None = None
    receivable_entity_id: str | None = None
    receivable_amount: float | None = None
    party_type: str | None = None
    party_id: str | None = None
    source_document_ref: str | None = None
    transaction_number: str | None = None
    posted_by: str | None = None
    payment_timing: str | None = "pay_now"
    linked_journal_id: str | None = None
    apply_credit_amount: float | None = None
    created_by_user_id: str | None = None
    lines: list[JournalLineCreate] = []
    reason: str | None = None
    # Expense-linked fields (SRS 1.1.1: every transaction must have a journal)
    expense_type: str | None = None   # e.g. "Bike Rent", "Fuel", etc.
    rider_id: str | None = None        # optional rider the expense is for

class JournalReverseRequest(BaseModel):
    reason: str
    owner_note: str | None = None


class VendorPaymentRequest(BaseModel):
    amount: float
    drawer_id: str
    payment_method: str
    entry_date: str | None = None
    description: str | None = None


def _get_vendor_open_credit_rows(vendor_id: str):
    try:
        rpc_res = supabase.rpc("fn_get_vendor_open_credits", {"p_vendor_id": vendor_id}).execute()
        return rpc_res.data or []
    except Exception:
        # Fallback when migration is not yet applied.
        rows = supabase.table("journals") \
            .select("id, entry_date, description, receivable_amount") \
            .eq("status", "posted") \
            .eq("is_receivable", True) \
            .eq("party_type", "vendor") \
            .eq("party_id", vendor_id) \
            .order("entry_date") \
            .execute()
        fallback = []
        for r in (rows.data or []):
            fallback.append({
                "journal_id": r.get("id"),
                "entry_date": r.get("entry_date"),
                "description": r.get("description"),
                "total_receivable": float(r.get("receivable_amount") or 0),
                "applied_amount": 0,
                "open_amount": float(r.get("receivable_amount") or 0),
            })
        return fallback


def _recompute_payable_settlement(source_journal_id: str):
    src = supabase.table("journals").select("id, total_amount, original_payable_amount").eq("id", source_journal_id).single().execute()
    if not src.data:
        return

    original = float(src.data.get("original_payable_amount") or src.data.get("total_amount") or 0)
    try:
        st = supabase.table("journal_settlements") \
            .select("amount") \
            .eq("source_journal_id", source_journal_id) \
            .execute()
        settled = sum(float(x.get("amount") or 0) for x in (st.data or []))
    except Exception:
        settled = 0

    outstanding = max(original - settled, 0)
    if outstanding == 0 and original > 0:
        status = "settled"
    elif settled > 0:
        status = "partially_settled"
    elif original > 0:
        status = "open"
    else:
        status = "na"

    supabase.table("journals").update({
        "original_payable_amount": original,
        "settled_amount": settled,
        "outstanding_amount": outstanding,
        "settlement_status": status,
    }).eq("id", source_journal_id).execute()


def _apply_vendor_credit_to_payable(*, vendor_id: str, target_journal_id: str, requested_amount: float, user_id: str | None):
    if requested_amount <= 0:
        return 0.0

    open_rows = _get_vendor_open_credit_rows(vendor_id)
    remaining = requested_amount
    applied_total = 0.0

    for row in open_rows:
        open_amount = float(row.get("open_amount") or 0)
        if open_amount <= 0:
            continue
        take = min(open_amount, remaining)
        if take <= 0:
            continue

        supabase.table("journal_settlements").insert({
            "source_journal_id": row.get("journal_id"),
            "target_journal_id": target_journal_id,
            "settlement_type": "credit_apply",
            "amount": take,
            "note": "Vendor receivable credit applied to payable",
            "created_by_user_id": user_id,
        }).execute()

        remaining -= take
        applied_total += take

        if remaining <= 0:
            break

    return applied_total


@app.get("/journals")
def list_journals():
    """Fetch all journals with their journal_lines."""
    try:
        res = supabase.table("journals") \
            .select("*, journal_lines(*)") \
            .order("created_at", desc=True) \
            .execute()

        return {"journals": res.data or []}
    except Exception as e:
        print(f"Error fetching journals: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to fetch journals: {str(e)}"
        )


@app.get("/vendors/{vendor_id}/open-credit-summary")
def get_vendor_open_credit_summary(vendor_id: str, user=Depends(require_role(["ACCOUNTANT", "PRO"]))):
    try:
        rows = _get_vendor_open_credit_rows(vendor_id)
        total_open = sum(float(r.get("open_amount") or 0) for r in rows)
        return {
            "vendor_id": vendor_id,
            "open_credit_total": total_open,
            "items": rows,
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch open credits: {e}")


@app.post("/journals")
def create_journal(
    journal: JournalCreate,
    user=Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    """
    Creates a journal row and its journal_lines in one transaction.
    The DB trigger fn_journal_to_ledger will auto-populate the ledger
    whenever a line is inserted.
    """
    try:
        if journal.status not in ("draft", "posted", "reversed"):
            raise HTTPException(status_code=400, detail="Invalid status")

        payment_timing = (journal.payment_timing or "pay_now").strip().lower()
        if payment_timing not in ("pay_now", "pay_later"):
            raise HTTPException(status_code=400, detail="payment_timing must be pay_now or pay_later")

        party_type = (journal.party_type or journal.receivable_entity_type or "").strip().lower() or None
        party_id = (journal.party_id or journal.receivable_entity_id or "").strip() or None

        if party_type and party_type not in ["vendor", "supplier", "rider"]:
            raise HTTPException(status_code=400, detail="party_type must be vendor, supplier, or rider")

        if party_type and not party_id:
            raise HTTPException(status_code=400, detail="party_id is required when party_type is set")

        if party_type == "supplier":
            if float(journal.vat_rate or 0) != 0 or float(journal.vat_amount or 0) != 0:
                raise HTTPException(status_code=400, detail="Supplier flow does not allow VAT")

        if party_type and party_id:
            table_name = "riders"
            if party_type == "vendor":
                table_name = "vendors"
            elif party_type == "supplier":
                table_name = "suppliers"

            party_exists = supabase.table(table_name).select("id").eq("id", party_id).limit(1).execute()
            if not party_exists.data:
                raise HTTPException(status_code=400, detail=f"Invalid {party_type} party_id")

        if journal.is_payable and payment_timing == "pay_now":
            if not journal.drawer_id or not journal.payment_method:
                raise HTTPException(
                    status_code=400,
                    detail="drawer_id and payment_method are required for pay_now payable journals",
                )

        if journal.is_payable and payment_timing == "pay_later":
            # Explicitly allow posting payable accrual without immediate cash movement.
            journal.drawer_id = None
            journal.payment_method = None

        if journal.is_receivable and journal.receivable_entity_type == "rider":
            if journal.receivable_amount is None or float(journal.receivable_amount) <= 0:
                raise HTTPException(
                    status_code=400,
                    detail="receivable_amount is required and must be > 0 for rider receivable journals",
                )

        journal_id = str(uuid.uuid4())

        requested_status = (journal.status or "draft").strip().lower()
        
        # If user is accountant, always post directly and skip drafts
        if user["role"] == "accountant":
            requested_status = "posted"

        header_status = "draft" if requested_status == "posted" else requested_status

        # 1. Insert journal header
        journal_data = {
            "id": journal_id,
            "entry_date": journal.entry_date,
            "description": journal.description,
            "status": header_status,
            "is_receivable": journal.is_receivable,
            "is_payable": journal.is_payable,
            "payment_timing": payment_timing,
            "linked_journal_id": journal.linked_journal_id,
        }
        if journal.type:
            journal_data["type"] = journal.type
        if journal.created_by_role:
            journal_data["created_by_role"] = journal.created_by_role
        if journal.total_amount is not None:
            journal_data["total_amount"] = journal.total_amount
        if journal.base_amount is not None:
            journal_data["base_amount"] = journal.base_amount
        if journal.vat_rate is not None:
            journal_data["vat_rate"] = journal.vat_rate
        if journal.vat_amount is not None:
            journal_data["vat_amount"] = journal.vat_amount
        if journal.payment_method:
            journal_data["payment_method"] = journal.payment_method
        if journal.drawer_id:
            journal_data["drawer_id"] = journal.drawer_id
        if party_type:
            journal_data["party_type"] = party_type
            journal_data["receivable_entity_type"] = party_type
        if party_id:
            journal_data["party_id"] = party_id
            journal_data["receivable_entity_id"] = party_id
        if journal.receivable_amount is not None:
            journal_data["receivable_amount"] = journal.receivable_amount
        if journal.created_by_user_id:
            journal_data["created_by_user_id"] = journal.created_by_user_id
        if journal.source_document_ref:
            journal_data["source_document_ref"] = journal.source_document_ref
        if journal.transaction_number:
            journal_data["transaction_number"] = journal.transaction_number

        if journal.posted_by:
            journal_data["posted_by"] = journal.posted_by
        if journal.rider_id:
            journal_data["rider_id"] = journal.rider_id

        if journal.is_payable:
            original = float(journal.total_amount or 0)
            if payment_timing == "pay_later" and party_type == "vendor":
                journal.total_amount = 0
                journal.base_amount = 0
                journal.vat_amount = 0
            journal_data["original_payable_amount"] = original
            journal_data["settled_amount"] = 0
            journal_data["outstanding_amount"] = original
            journal_data["settlement_status"] = "open" if original > 0 else "na"

        # Keep receivable rider link consistent when only rider_id is provided.
        if journal.is_receivable and journal.rider_id and not party_id:
            journal_data["receivable_entity_type"] = "rider"
            journal_data["receivable_entity_id"] = journal.rider_id
            journal_data["party_type"] = "rider"
            journal_data["party_id"] = journal.rider_id

        res = supabase.table("journals").insert(journal_data).execute()

        if not res.data:
            raise HTTPException(status_code=500, detail="Failed to insert journal")

        # Optional credit application on payable vendor journals.
        applied_credit = 0.0
        if journal.is_payable and party_type == "vendor":
            requested_credit = float(journal.apply_credit_amount or 0)
            if requested_credit > 0:
                applied_credit = _apply_vendor_credit_to_payable(
                    vendor_id=party_id,
                    target_journal_id=journal_id,
                    requested_amount=requested_credit,
                    user_id=journal.created_by_user_id,
                )
                _recompute_payable_settlement(journal_id)

        # 2. Insert journal_lines
        if journal.lines:
            lines_data = []
            for line in journal.lines:
                lines_data.append({
                    "journal_id": journal_id,
                    "account_id": line.account_id,
                    "debit_amount": line.debit_amount,
                    "credit_amount": line.credit_amount,
                    "drawer_id": line.drawer_id,
                    "party_type": party_type,
                    "party_id": party_id,
                })
            supabase.table("journal_lines").insert(lines_data).execute()

        # 3. Only insert into expenses if authenticated user role is PRO (not accountant)
        expense_row = None
        if journal.type == "expense" and user["role"] == "pro":
            expense_data = {
                "expense_type": journal.description,
                "amount": journal.total_amount or 0,
                "base_amount": journal.base_amount if journal.base_amount is not None else (journal.total_amount or 0),
                "vat_rate": journal.vat_rate or 0,
                "vat_amount": journal.vat_amount or 0,
                "expense_date": journal.entry_date,
                "description": journal.description,
                "status": "pending",
                "journal_id": journal_id,
                "created_by_role": journal.created_by_role,
            }
            if journal.rider_id:
                expense_data["rider_id"] = journal.rider_id
            elif journal.receivable_entity_type == "rider" and journal.receivable_entity_id:
                expense_data["rider_id"] = journal.receivable_entity_id

            exp_res = supabase.table("expenses").insert(expense_data).execute()
            expense_row = exp_res.data[0] if exp_res.data else None


        # 4. Post only after lines exist, so ledger posting triggers run consistently.
        if requested_status == "posted":
            supabase.table("journals").update({"status": "posted"}).eq("id", journal_id).execute()

            # If this is a pay_now vendor payment, reduce the drawer's cached balance
            if journal.is_payable and payment_timing == "pay_now" and journal.drawer_id and journal.total_amount:
                try:
                    # Fetch current drawer balance
                    drawer_res = supabase.table("drawer").select("balance").eq("id", journal.drawer_id).single().execute()
                    if drawer_res.data and "balance" in drawer_res.data:
                        new_balance = float(drawer_res.data["balance"]) - float(journal.total_amount)
                        supabase.table("drawer").update({"balance": new_balance}).eq("id", journal.drawer_id).execute()
                except Exception as e:
                    print(f"Warning: drawer balance update failed (pay_now vendor): {e}")

        # 5. Re-fetch the complete journal with lines
        full = supabase.table("journals") \
            .select("*, journal_lines(*)") \
            .eq("id", journal_id) \
            .single() \
            .execute()

        result = {
            "message": "Journal created successfully",
            "journal": full.data,
            "applied_credit_amount": applied_credit,
        }
        if expense_row:
            result["expense"] = expense_row

        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to create journal: {str(e)}"
        )


@app.post("/journals/{journal_id}/pay-vendor")
def pay_vendor_later(
    journal_id: str,
    payload: VendorPaymentRequest,
    user=Depends(require_role("ACCOUNTANT")),
):
    try:
        original_res = supabase.table("journals") \
            .select("id, status, is_payable, party_type, party_id, outstanding_amount, settlement_status") \
            .eq("id", journal_id) \
            .single() \
            .execute()
        original = original_res.data
        if not original:
            raise HTTPException(status_code=404, detail="Original payable journal not found")

        if original.get("status") != "posted":
            raise HTTPException(status_code=400, detail="Only posted payable journals can be paid")

        if not original.get("is_payable"):
            raise HTTPException(status_code=400, detail="Journal is not marked as payable")

        if (original.get("party_type") or "").lower() != "vendor":
            raise HTTPException(status_code=400, detail="This endpoint is only for vendor payable journals")

        outstanding = float(original.get("outstanding_amount") or 0)
        if outstanding <= 0:
            raise HTTPException(status_code=400, detail="Journal is already fully settled")

        pay_amount = float(payload.amount)
        if pay_amount <= 0:
            raise HTTPException(status_code=400, detail="Payment amount must be greater than zero")
        if pay_amount > outstanding:
            raise HTTPException(status_code=400, detail=f"Payment amount cannot exceed outstanding {outstanding}")

        entry_date = payload.entry_date or datetime.now().strftime("%Y-%m-%d")
        description = payload.description or f"Vendor payment settlement for {journal_id}"
        payment_journal_id = str(uuid.uuid4())

        payment_header = {
            "id": payment_journal_id,
            "entry_date": entry_date,
            "description": description,
            "status": "draft",
            "type": "manual_adjustment",
            "created_by_role": "accountant",
            "created_by_user_id": user["id"],
            "approved_by": user["id"],
            "approved_at": datetime.now().isoformat(),
            "payment_method": payload.payment_method,
            "drawer_id": payload.drawer_id,
            "is_receivable": False,
            "is_payable": False,
            "payment_timing": "pay_now",
            "total_amount": pay_amount,
            "base_amount": pay_amount,
            "vat_rate": 0,
            "vat_amount": 0,
            "party_type": "vendor",
            "party_id": original.get("party_id"),
            "receivable_entity_type": "vendor",
            "receivable_entity_id": original.get("party_id"),
            "linked_journal_id": journal_id,
        }

        supabase.table("journals").insert(payment_header).execute()

        drawer_res = supabase.table("drawer").select("name").eq("id", payload.drawer_id).single().execute()
        db_drawer_name = drawer_res.data.get("name") if drawer_res.data else "Bank"
        drawer_account_id = "CASH-BANK"
        if db_drawer_name == "Cash": drawer_account_id = "CASH-MAIN"
        if db_drawer_name == "Noqodi": drawer_account_id = "CASH-NOQODI"

        supabase.table("journal_lines").insert([
            {
                "journal_id": payment_journal_id,
                "account_id": "vendor_payable",
                "debit_amount": pay_amount,
                "credit_amount": 0,
                "party_type": "vendor",
                "party_id": original.get("party_id"),
            },
            {
                "journal_id": payment_journal_id,
                "account_id": drawer_account_id,
                "debit_amount": 0,
                "credit_amount": pay_amount,
                "drawer_id": payload.drawer_id,
                "party_type": "vendor",
                "party_id": original.get("party_id"),
            },
        ]).execute()

        # Post after lines are inserted so journal->ledger update trigger can execute.
        supabase.table("journals").update({"status": "posted"}).eq("id", payment_journal_id).execute()

        supabase.table("journal_settlements").insert({
            "source_journal_id": journal_id,
            "target_journal_id": payment_journal_id,
            "settlement_type": "payment",
            "amount": pay_amount,
            "note": "Pay-later vendor settlement payment",
            "created_by_user_id": user["id"],
        }).execute()

        _recompute_payable_settlement(journal_id)

        updated = supabase.table("journals").select("*").eq("id", journal_id).single().execute()
        payment = supabase.table("journals").select("*").eq("id", payment_journal_id).single().execute()

        return {
            "message": "Vendor payment posted successfully",
            "payment_journal": payment.data,
            "updated_original": updated.data,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to settle vendor payable: {e}")


@app.post("/journals/{journal_id}/approve")
def approve_journal(
    journal_id: str,
    data: JournalApprovalRequest | None = None,
    user = Depends(require_role("ACCOUNTANT"))
):
    """
    Accountant approves a draft journal:
    1. Validates journal is in draft status
    2. Inserts journal_lines from accountant input
    3. Updates journal: status=posted, drawer, payment_method, receivable fields
    4. Cascades expense status to 'approved'
    5. Resolves the linked action_item
    6. Writes audit_log
    7. Updates drawer cached balance
    """
    try:
        # Fetch current journal with full data
        current = supabase.table("journals") \
            .select("*") \
            .eq("id", journal_id) \
            .single() \
            .execute()

        if not current.data:
            raise HTTPException(status_code=404, detail="Journal not found")

        old_journal = current.data

        if old_journal["status"] == "posted":
            return {"message": "Journal already approved"}

        if old_journal["status"] != "draft":
            raise HTTPException(
                status_code=400,
                detail=f"Cannot approve journal with status '{old_journal['status']}'"
            )

        # Use provided data or fall back to defaults
        if data and data.drawer_id:
            drawer_id = data.drawer_id
            payment_method = data.payment_method
        else:
            # Fallback: fetch default 'Cash' drawer
            drawer_res = supabase.table("drawer").select("id").eq("name", "Cash").execute()
            drawer_id = drawer_res.data[0]["id"] if drawer_res.data else None
            payment_method = "cash"

        # Step 1: Insert journal_lines if provided by accountant
        if data and data.lines:
            # Delete any existing draft lines first
            supabase.table("journal_lines") \
                .delete() \
                .eq("journal_id", journal_id) \
                .execute()

            lines_data = []
            for line in data.lines:
                lines_data.append({
                    "journal_id": journal_id,
                    "account_id": line.get("account_id", ""),
                    "debit_amount": line.get("debit_amount", 0),
                    "credit_amount": line.get("credit_amount", 0),
                    "drawer_id": line.get("drawer_id"),
                })
            if lines_data:
                supabase.table("journal_lines").insert(lines_data).execute()

        # Step 2: Build journal update data
        update_data = {
            "status": "posted",
            "payment_method": payment_method,
            "approved_by": user["id"],
            "approved_at": datetime.now().isoformat(),
        }
        if drawer_id:
            update_data["drawer_id"] = drawer_id

        if data:
            update_data["is_receivable"] = data.is_receivable
            if data.is_receivable and data.receivable_amount is not None:
                update_data["receivable_amount"] = data.receivable_amount
                # Get rider_id from the linked expense for receivable_entity_id
                exp_res = supabase.table("expenses") \
                    .select("rider_id") \
                    .eq("journal_id", journal_id) \
                    .execute()
                if exp_res.data:
                    update_data["receivable_entity_type"] = "rider"
                    update_data["receivable_entity_id"] = exp_res.data[0]["rider_id"]

                # Fallback: if journal has direct rider_id, keep receivable binding rider-specific.
                if not update_data.get("receivable_entity_id") and old_journal.get("rider_id"):
                    update_data["receivable_entity_type"] = "rider"
                    update_data["receivable_entity_id"] = old_journal.get("rider_id")

        res = supabase.table("journals") \
            .update(update_data) \
            .eq("id", journal_id) \
            .execute()

        # Step 3: Cascade approval to linked expense row
        supabase.table("expenses") \
            .update({"status": "approved"}) \
            .eq("journal_id", journal_id) \
            .execute()

        # Step 4: Resolve the linked action_item in DB
        try:
            action_res = supabase.table("action_items") \
                .select("id") \
                .eq("reference_id", journal_id) \
                .eq("type", "journal_pending_approval") \
                .is_("resolved_at", "null") \
                .execute()
            if action_res.data:
                for action in action_res.data:
                    supabase.table("action_items") \
                        .update({
                            "resolved_at": datetime.now().isoformat(),
                            "resolved_by": user["id"],
                            "resolution_notes": "Journal approved and posted by accountant",
                        }) \
                        .eq("id", action["id"]) \
                        .execute()
        except Exception as e:
            print(f"Warning: failed to resolve action_item: {e}")

        # Step 5: Update drawer cached balance
        if drawer_id:
            try:
                amount = old_journal.get("total_amount", 0)
                supabase.table("drawer") \
                    .update({"balance": supabase.table("drawer").select("balance").eq("id", drawer_id).single().execute().data["balance"] - float(amount)}) \
                    .eq("id", drawer_id) \
                    .execute()
            except Exception as e:
                print(f"Warning: drawer balance update failed: {e}")

        # Step 6: Write audit_log
        write_audit_log(
            table_name="journals",
            record_id=journal_id,
            action="UPDATE",
            old_data={"status": old_journal["status"]},
            new_data=update_data,
            user_id=user["id"],
        )

        return {
            "message": "Journal approved successfully",
            "journal": res.data[0] if res.data else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to approve journal: {str(e)}"
        )


@app.post("/journals/{journal_id}/reverse")
def reverse_journal(
    journal_id: str,
    data: JournalReverseRequest,
    user = Depends(require_role("ACCOUNTANT"))
):
    """
    Reverses a Posted journal by:
    1. Setting original status to 'Reversed'
    2. Creating a new 'Posted' journal with swapped lines
    3. Linking via reversal_of_journal_id
    """
    try:
        # 1. Fetch original journal with lines
        res = supabase.table("journals") \
            .select("*, journal_lines(*)") \
            .eq("id", journal_id) \
            .single() \
            .execute()

        original = res.data
        if not original:
            raise HTTPException(status_code=404, detail="Journal not found")

        if original["status"] != "posted":
            raise HTTPException(
                status_code=400,
                detail=f"Only 'posted' journals can be reversed. Current status: {original['status']}"
            )

        # Optional timelock (disabled by default): require owner note for old journals.
        if JOURNAL_REVERSAL_TIMELOCK_DAYS > 0:
            created_at_raw = original.get("created_at") or original.get("entry_date")
            created_at_dt = None
            try:
                if created_at_raw:
                    created_at_dt = parse_date(str(created_at_raw))
            except Exception:
                created_at_dt = None
            if created_at_dt is not None:
                age_days = (datetime.now() - created_at_dt).days
                if age_days > JOURNAL_REVERSAL_TIMELOCK_DAYS and not (data.owner_note or "").strip():
                    raise HTTPException(
                        status_code=400,
                        detail=(
                            f"Journal is older than {JOURNAL_REVERSAL_TIMELOCK_DAYS} days. "
                            "Owner note is required to reverse this journal."
                        ),
                    )

        lines = original.get("journal_lines", [])
        if not lines:
             raise HTTPException(status_code=400, detail="Journal has no lines to reverse")

        # 2. Create reversal header
        reversal_id = str(uuid.uuid4())
        reversal_data = {
            "id": reversal_id,
            "entry_date": datetime.now().strftime("%Y-%m-%d"),
            "description": f"(Reversal: {data.reason}) {original['description']}",
            "status": "posted",
            "type": original.get("type"),
            "created_by_role": user["role"],
            "created_by_user_id": user["id"],
            "reversal_of_journal_id": journal_id,
            "total_amount": original.get("total_amount"),
            "payment_method": original.get("payment_method"),
            "drawer_id": original.get("drawer_id"),
        }
        if (data.owner_note or "").strip():
            reversal_data["source_document_ref"] = f"owner_note: {(data.owner_note or '').strip()}"

        # Insert reversal
        rev_res = supabase.table("journals").insert(reversal_data).execute()
        if not rev_res.data:
            raise HTTPException(status_code=500, detail="Failed to create reversal journal")

        # 3. Create swapped lines
        rev_lines = []
        for line in lines:
            rev_lines.append({
                "journal_id": reversal_id,
                "account_id": line["account_id"],
                "debit_amount": line["credit_amount"],   # SWAP
                "credit_amount": line["debit_amount"],   # SWAP
                "drawer_id": line.get("drawer_id")
            })

        supabase.table("journal_lines").insert(rev_lines).execute()

        # 4. Update original journal status
        supabase.table("journals") \
            .update({"status": "reversed"}) \
            .eq("id", journal_id) \
            .execute()

        # 4b. Cascade reversal to linked expense
        supabase.table("expenses") \
            .update({"status": "rejected"}) \
            .eq("journal_id", journal_id) \
            .execute()

        # 5. Return the new reversal journal
        full_rev = supabase.table("journals") \
            .select("*, journal_lines(*)") \
            .eq("id", reversal_id) \
            .single() \
            .execute()

        return {
            "message": "Journal reversed successfully",
            "journal": full_rev.data
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"Reversal Error: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to reverse journal: {str(e)}"
        )


# --- Ledger Module ---

@app.get("/ledger")
def get_ledger(
    account: str | None = None,
    rider_id: str | None = None,
    from_date: str | None = None,
    to_date: str | None = None,
    user = Depends(require_role("ACCOUNTANT")),
):
    """
    Fetch read-only ledger entries. The ledger is auto-populated by
    the fn_journal_to_ledger trigger when a journal is posted.
    Supports optional filters: account name, date range.
    """
    try:
        query = supabase.table("ledger") \
            .select("*, journals(description, entry_date, rider_id, receivable_entity_type)") \
            .order("posted_at", desc=True)

        if account:
            query = query.eq("account_id", account)

        if rider_id:
            # Strictly filter for only the selected rider's ledger entries
            # Only include entries where the joined journal's rider_id matches and receivable_entity_type is null or 'rider'
            query = query.eq("journals.rider_id", rider_id)
            query = query.or_("journals.receivable_entity_type.is.null(),journals.receivable_entity_type.eq.rider")

        if from_date:
            query = query.gte("posted_at", from_date)

        if to_date:
            query = query.lte("posted_at", to_date + "T23:59:59")

        res = query.execute()

        return {"ledger": res.data or []}
    except Exception as e:
        print(f"Error fetching ledger: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to fetch ledger: {str(e)}"
        )


@app.get("/ledger/accounts")
def get_ledger_accounts(
    user = Depends(require_role("ACCOUNTANT")),
):
    """Returns distinct account names used in the ledger."""
    try:
        res = supabase.table("ledger") \
            .select("account_id") \
            .execute()

        accounts = list({row["account_id"] for row in (res.data or []) if row.get("account_id")})
        accounts.sort()

        return {"accounts": accounts}
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to fetch ledger accounts: {str(e)}"
        )


@app.get("/ledger/summary")
def get_ledger_summary(
    user = Depends(require_role("ACCOUNTANT")),
):
    """
    Returns aggregated debit/credit totals per account.
    Useful for a trial balance view.
    """
    try:
        res = supabase.table("ledger") \
            .select("account_id, debit_amount, credit_amount") \
            .execute()

        summary: dict = {}
        for row in res.data or []:
            acct = row.get("account_id", "Unknown")
            d = float(row.get("debit_amount") or 0)
            c = float(row.get("credit_amount") or 0)

            if acct not in summary:
                summary[acct] = {"account": acct, "total_debit": 0.0, "total_credit": 0.0}
            summary[acct]["total_debit"] += d
            summary[acct]["total_credit"] += c

        result = list(summary.values())
        for item in result:
            item["balance"] = item["total_debit"] - item["total_credit"]

        return {"summary": result}
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to fetch ledger summary: {str(e)}"
        )


# --- Reports Module ---

@app.get("/reports/summary")

def get_report_summary(
    user = Depends(require_role(["ACCOUNTANT", "PRO"])),
):
    """
    Returns aggregated financial truth explicitly powered by the immutable general ledger.
    Matches the schema expected by `FinancialReportModel`.
    """
    try:
        # Fetch all posted journals for recoverable/non-recoverable info
        journals_res = supabase.table("journals").select("id, type, base_amount, total_amount, is_receivable, receivable_amount, status, batch_id, category, receivable_entity_type, party_type").eq("status", "posted").execute()
        journals = journals_res.data or []

        # Fetch finalized payslips and finalized payroll batches
        payslips_res = supabase.table("payslips").select("gross_salary, net_salary, batch_id").execute()
        batch_ids = list({p.get("batch_id") for p in (payslips_res.data or []) if p.get("batch_id")})
        finalized_batches = set()
        if batch_ids:
            batch_res = supabase.table("payroll_batches").select("id, status").in_("id", batch_ids).eq("status", "finalized").execute()
            finalized_batches = set(b["id"] for b in (batch_res.data or []))

        # Revenue & Net Pay: Only from finalized payslips
        total_revenue = 0.0
        total_net_pay = 0.0
        if payslips_res.data:
            for p in payslips_res.data:
                batch_id = p.get("batch_id")
                if batch_id and batch_id in finalized_batches:
                    total_revenue += float(p.get("gross_salary") or 0)
                    total_net_pay += float(p.get("net_salary") or 0)


        # Non-Recoverable Expenses: is_receivable = False OR vendor journal
        def is_vendor_journal(j):
            return (j.get("receivable_entity_type") == "vendor" or j.get("party_type") == "vendor")

        non_recoverable_expenses = [j for j in journals if not j.get("is_receivable") or is_vendor_journal(j)]
        non_recoverable_total = 0.0
        for j in non_recoverable_expenses:
            try:
                non_recoverable_total += float(j.get("base_amount") or 0)
            except Exception:
                continue

        # Recoverable Expenses: is_receivable = True, use base_amount only
        recoverable_expenses = [j for j in journals if j.get("is_receivable")]
        recoverable_total = sum(float(j.get("base_amount") or 0) for j in recoverable_expenses)

        # Separate Fines & Expenses in Recoverable Section
        fines = [j for j in recoverable_expenses if j.get("type") == "fine"]
        expenses = [j for j in recoverable_expenses if j.get("type") == "expense"]
        fines_total = sum(float(j.get("base_amount") or 0) for j in fines)
        recoverable_expenses_total = sum(float(j.get("base_amount") or 0) for j in expenses)

        # Add all recoverable expenses and all recoverable fines
        total_recoverable = fines_total + recoverable_expenses_total

        # Expense Breakdown by Category (non-recoverable + vendor journals)
        expense_breakdown_map = {}
        for j in non_recoverable_expenses:
            try:
                cat = j.get("category") or j.get("type") or "Other"
                amt = float(j.get("base_amount") or 0)
                if cat not in expense_breakdown_map:
                    expense_breakdown_map[cat] = 0.0
                expense_breakdown_map[cat] += amt
            except Exception:
                continue
        expense_breakdown = [
            {"label": k, "amount": v} for k, v in expense_breakdown_map.items() if v > 0
        ]

        # Company Expenses = Non-Recoverable + Recoverable (fines + recoverable expenses)
        total_company_expense = non_recoverable_total + recoverable_total

        # Net Profit = Net Pay - Company Expenses
        net_profit = total_net_pay - total_company_expense

        # Recovery section for frontend
        recovery = []
        if fines_total > 0:
            recovery.append({"label": "Fines", "amount": fines_total})
        if recoverable_expenses_total > 0:
            recovery.append({"label": "Expenses", "amount": recoverable_expenses_total})

        # Return all fields expected by frontend, defaulting to zero/empty if not present
        return {
            "total_revenue": total_revenue,
            "total_expense": non_recoverable_total,  # Only non-recoverable for expense card
            "net_profit": net_profit,
            "total_net_pay": total_net_pay,
            "total_company_expense": total_company_expense,
            "recoverable_amount": recoverable_total,
            "recoverable_journals": recoverable_expenses_total,
            "non_recoverable_expense": non_recoverable_total,
            "recoverable_outstanding": 0.0,
            "recoverable_collected": 0.0,
            "recoverable_created": 0.0,
            "expense_breakdown": expense_breakdown,
            "deductions": [],
            "recovery": recovery
        }
    except Exception as e:
        print(f"Error fetching report summary: {e}")
        raise HTTPException(
            status_code=400,
            detail=f"Failed to fetch report summary: {str(e)}"
        )


@app.get("/reports/rider/{rider_id}")
def get_rider_statement(
    rider_id: str,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    """
    Returns historical earnings and deductions for a specific rider.
    """
    try:
        # Fetch ledger entries for this rider using the denormalized rider_id column
        res = supabase.table("ledger") \
            .select("*, journals(description, entry_date)") \
            .eq("rider_id", rider_id) \
            .order("posted_at", desc=True) \
            .execute()
            
        return {"statement": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch rider statement: {str(e)}")


@app.get("/reports/rider/{rider_id}/summary")
def get_rider_statement_summary(
    rider_id: str,
    user = Depends(require_role(["ACCOUNTANT", "PRO"]))
):
    """Returns summarized rider statement analytics (totals, monthly, category split)."""
    try:
        res = supabase.rpc("fn_get_rider_statement_summary", {"p_rider_id": rider_id}).execute()
        summary = res.data
        if isinstance(summary, list) and summary:
            summary = summary[0]
        return {"summary": summary or {}}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch rider statement summary: {str(e)}")


@app.get("/reports/aging")
def get_fine_aging(user = Depends(require_role("ACCOUNTANT"))):
    """
    Calculates aging for unpaid traffic fines.
    """
    try:
        # Fetch unpaid fines
        res = supabase.table("traffic_fines") \
            .select("amount, violation_date") \
            .neq("status", "fully_recovered") \
            .execute()
            
        today = datetime.now().date()
        aging = {
            "0-30 days": 0.0,
            "31-60 days": 0.0,
            "61+ days": 0.0
        }
        
        for fine in res.data or []:
            v_date = datetime.fromisoformat(fine["violation_date"]).date()
            diff = (today - v_date).days
            amount = float(fine["amount"] or 0)
            
            if diff <= 30:
                aging["0-30 days"] += amount
            elif diff <= 60:
                aging["31-60 days"] += amount
            else:
                aging["61+ days"] += amount
                
        return {"aging": aging}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch fine aging: {str(e)}")


# --- Audit Log Module ---

@app.get("/audit-log")
def get_audit_log(
    table_name: str | None = None,
    record_id: str | None = None,
    limit: int = 100,
    user = Depends(require_role("ACCOUNTANT")),
):
    """Fetch audit log entries with optional filters."""
    try:
        query = supabase.table("audit_log") \
            .select("*") \
            .order("changed_at", desc=True) \
            .limit(limit)

        if table_name:
            query = query.eq("table_name", table_name)

        if record_id:
            query = query.eq("record_id", record_id)

        res = query.execute()

        return {"audit_log": res.data or []}
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to fetch audit log: {str(e)}"
        )


# Payroll Module

class PayrollRow(BaseModel):
    external_id: str
    gross_salary: float
    raw_data: dict

class PayrollUploadRequest(BaseModel):
    month: str
    platform: str  # "Talabat" or "Keeta"
    rows: list[PayrollRow]

class PayrollUploadResponse(BaseModel):
    batch_id: str
    message: str
    payslips_created: int
    unmatched_ids: list[str]

class PayrollFinalizeRequest(BaseModel):
    drawer_id: str
    payment_method: str = "bank_transfer"
    # Legacy fields kept optional for backward compatibility.
    message: str | None = None
    payslips_created: int | None = None
    unmatched_ids: list[str] = Field(default_factory=list)


# Async payroll upload jobs (in-memory).
# Backward compatible: existing /payroll/upload endpoint remains unchanged.
PAYROLL_UPLOAD_JOBS: dict[str, dict] = {}
PAYROLL_UPLOAD_JOBS_LOCK = Lock()


def _set_upload_job(job_id: str, patch: dict):
    with PAYROLL_UPLOAD_JOBS_LOCK:
        current = PAYROLL_UPLOAD_JOBS.get(job_id, {})
        current.update(patch)
        PAYROLL_UPLOAD_JOBS[job_id] = current


def _run_payroll_upload_job(job_id: str, request_payload: dict):
    _set_upload_job(
        job_id,
        {
            "status": "processing",
            "progress": 10,
            "started_at": datetime.now().isoformat(),
            "error": None,
        },
    )
    try:
        req = PayrollUploadRequest(**request_payload)
        _set_upload_job(job_id, {"progress": 35, "stage": "validating and matching"})
        result = upload_payroll(req)
        _set_upload_job(
            job_id,
            {
                "status": "completed",
                "progress": 100,
                "stage": "completed",
                "finished_at": datetime.now().isoformat(),
                "result": result,
            },
        )
    except HTTPException as e:
        _set_upload_job(
            job_id,
            {
                "status": "failed",
                "progress": 100,
                "stage": "failed",
                "finished_at": datetime.now().isoformat(),
                "error": str(e.detail),
            },
        )
    except Exception as e:
        _set_upload_job(
            job_id,
            {
                "status": "failed",
                "progress": 100,
                "stage": "failed",
                "finished_at": datetime.now().isoformat(),
                "error": str(e),
            },
        )


class PayslipDeductionEditRequest(BaseModel):
    item_index: int
    new_amount: float
    reason: str | None = None
    expected_label: str | None = None


class PayslipItemsReplaceRequest(BaseModel):
    items: list[dict]
    reason: str | None = None


class CarryForwardEntryChoice(BaseModel):
    entry_id: str
    decision: str  # all | some | none
    apply_amount: float | None = None


class CarryForwardApplyRequest(BaseModel):
    selections: list[CarryForwardEntryChoice]


def clean_platform_id(raw_id: any) -> str:
    """
    Cleans platform IDs from Excel (handling scientific notation, decimals, spaces).
    Ensures consistent string conversion for comparison.
    """
    if raw_id is None:
        return ""
    
    try:
        val = str(raw_id).strip()
        # Handle scientific notation e.g. 1.75508e+15 or simple decimals 12345.0
        if 'e' in val.lower() or '.' in val:
            try:
                f_val = float(val)
                # If it's effectively an integer (e.g. 12345.0), convert to int then str
                if f_val == int(f_val):
                    val = str(int(f_val))
                else:
                    # Specific formatting to prevent scientific notation in string result
                    val = "{:f}".format(f_val)
                    if '.' in val:
                        val = val.rstrip('0').rstrip('.')
            except:
                pass
        
        # Final cleanup: trim any trailing .0 or spaces
        if val.endswith('.0'):
            val = val[:-2]
            
        return val.strip()
    except Exception as e:
        print(f"Error cleaning ID {raw_id}: {e}")
        return str(raw_id).strip()


def build_payslip_review_meta(payslip: dict) -> dict:
    """
    Build lightweight review flags without changing existing status flow.
    Flags are used by preview/finalization safety checks.
    """
    issue_codes: list[str] = []
    issue_snapshot: dict = {}

    net_salary = float(payslip.get("net_salary") or 0)
    status = str(payslip.get("status") or "").lower()

    if net_salary < 0:
        issue_codes.append("negative_net")
        issue_snapshot["net_salary"] = net_salary

    if status == "mismatch":
        issue_codes.append("alias_mismatch")
    elif status == "error":
        issue_codes.append("row_error")

    if not payslip.get("rider_id"):
        issue_codes.append("missing_rider")

    # Keep deterministic order in storage to avoid noisy updates.
    issue_codes = sorted(set(issue_codes))

    return {
        "review_required": len(issue_codes) > 0,
        "issue_codes": issue_codes,
        "issue_snapshot": issue_snapshot,
    }


def recalc_payslip_totals_from_items(items: list[dict]) -> dict:
    """
    Recalculate payslip totals from itemized rows.
    Compatibility rules:
    - earnings are positive numbers
    - deduction/fine/platform_deduction are negative numbers
    - total_fines = fine type only
    - total_expenses = deduction type only
    """
    normalized_items: list[dict] = []
    net_salary = 0.0
    total_fines = 0.0
    total_expenses = 0.0
    internal_fines = 0.0
    other_deductions = 0.0

    for item in items or []:
        try:
            amount = float(item.get("amount") or 0)
        except Exception:
            amount = 0.0

        if abs(amount) <= 0.0001:
            continue

        item_type = str(item.get("type") or "").strip().lower()
        label = str(item.get("label") or "").strip().lower()

        normalized_item = dict(item)
        normalized_item["amount"] = amount
        normalized_items.append(normalized_item)

        net_salary += amount

        if item_type == "fine":
            internal_fines += abs(amount)
            total_fines += abs(amount)
        elif item_type == "deduction":
            total_expenses += abs(amount)
            if "loan" in label or "uniform" in label:
                other_deductions += abs(amount)

    return {
        "items": normalized_items,
        "net_salary": net_salary,
        "total_fines": total_fines,
        "total_expenses": total_expenses,
        "internal_fines": internal_fines,
        "internal_expenses": total_expenses,
        "other_deductions": other_deductions,
    }


def group_payslip_deductions(items: list[dict]) -> dict:
    """
    Read-only grouping view for UI transparency.
    Output sections:
    - fines: internal, external, total
    - expenses: category-wise rows, total
    """
    fines_internal = 0.0
    fines_external = 0.0
    platform_adjustments = 0.0
    expense_by_label: dict[str, float] = {}

    for item in items or []:
        try:
            amount = float(item.get("amount") or 0)
        except Exception:
            amount = 0.0

        if abs(amount) <= 0.0001:
            continue

        item_type = str(item.get("type") or "").strip().lower()
        subtype = str(item.get("subtype") or "").strip().lower()
        label = str(item.get("label") or "Other").strip() or "Other"
        deduction_abs = abs(amount)

        if item_type == "fine":
            if subtype == "external_fine":
                fines_external += deduction_abs
            else:
                # default fine bucket is internal unless explicitly external
                fines_internal += deduction_abs
            continue

        # Platform deductions are tracked separately and are not external fines.
        if item_type == "platform_deduction":
            platform_adjustments += deduction_abs
            continue

        if item_type == "deduction":
            expense_by_label[label] = float(expense_by_label.get(label) or 0) + deduction_abs

    expense_rows = [
        {"label": k, "amount": v}
        for k, v in sorted(expense_by_label.items(), key=lambda kv: kv[0].lower())
    ]
    total_expenses = sum(row["amount"] for row in expense_rows)
    total_fines = fines_internal + fines_external

    return {
        "fines": {
            "internal_fines": fines_internal,
            "external_fines": fines_external,
            "total_fines": total_fines,
        },
        "expenses": {
            "rows": expense_rows,
            "total_expenses": total_expenses,
        },
        "platform_adjustments": platform_adjustments,
    }


def build_adjustment_history_entries(
    old_items: list[dict],
    new_items: list[dict],
    user_id: str,
    reason: str,
) -> list[dict]:
    """Generate immutable adjustment history entries for changed deduction-like rows."""
    entries: list[dict] = []
    max_len = max(len(old_items), len(new_items))

    def _norm_amount(item: dict | None) -> float:
        if not item:
            return 0.0
        try:
            return abs(float(item.get("amount") or 0))
        except Exception:
            return 0.0

    def _editable(item: dict | None) -> bool:
        if not item:
            return False
        return str(item.get("type") or "").lower() in {"deduction", "fine", "platform_deduction"}

    now_iso = datetime.now().isoformat()
    safe_reason = (reason or "UI adjustment").strip()

    for i in range(max_len):
        old_item = old_items[i] if i < len(old_items) else None
        new_item = new_items[i] if i < len(new_items) else None

        if not _editable(old_item) and not _editable(new_item):
            continue

        old_amount = _norm_amount(old_item)
        new_amount = _norm_amount(new_item)
        if abs(old_amount - new_amount) <= 0.0001 and old_item and new_item:
            continue

        label = str((new_item or old_item or {}).get("label") or "")
        item_type = str((new_item or old_item or {}).get("type") or "")
        action = "changed"
        if old_item is None and new_item is not None:
            action = "added"
        elif old_item is not None and new_item is None:
            action = "removed"

        reduced_amount = 0.0
        if old_amount > new_amount:
            reduced_amount = old_amount - new_amount

        entries.append({
            "entry_id": str(uuid.uuid4()),
            "item_index": i,
            "label": label,
            "type": item_type,
            "action": action,
            "old_amount": old_amount,
            "new_amount": new_amount,
            "reduced_amount": reduced_amount,
            "reason": safe_reason,
            "adjusted_by": user_id,
            "adjusted_at": now_iso,
        })

    return entries


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
    global_alias_map: dict = None, # platform_rider_id -> data
):
    """
    Optimized 6-step alias resolution logic using pre-fetched data.
    Returns (rider_id, alias_id, resolved_rider_name, rider_status_or_error, alias_update_data, action_item_data, result_flag)
    The result_flag can be None, "MATCHED", "ERROR", or "SKIP".
    """
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
                # This ID exists, but for a DIFFERENT platform.
                # Silently skip this according to the new strict matching rule.
                db_platform = global_match.get("platform", "Unknown")
                print(f"[PAYROLL_SKIP] {cleaned_id} found on {db_platform}, ignoring for {platform}")
                return global_match.get("rider_id"), None, rider_name, f"Cross-platform: {db_platform}", None, None, "SKIP"

        
        # Sort so we prioritize 'active' and 'valid_to is null'
        active_alias = next((a for a in platform_aliases if a["status"] == "active" and a["valid_to"] is None), None)
        if active_alias:
            r_name = (active_alias.get("rider") or {}).get("name") or rider_name
            r_status = (active_alias.get("rider") or {}).get("status") or "active"
            return active_alias["rider_id"], active_alias["id"], r_name, r_status, None, None, "MATCHED"

        # Step 3: Expired active alias
        expired_alias = next((a for a in platform_aliases if a["status"] == "active" and a["valid_to"] is not None), None)
        if expired_alias:
            r_name = (expired_alias.get("rider") or {}).get("name") or rider_name
            r_status = (expired_alias.get("rider") or {}).get("status") or "active"
            # Return update to clear valid_to
            return expired_alias["rider_id"], expired_alias["id"], r_name, r_status, {"id": expired_alias["id"], "valid_to": None}, None, "MATCHED"

        # Step 4: Inactive alias
        inactive_alias = next((a for a in platform_aliases if a["status"] == "inactive"), None)
        if inactive_alias:
            r_name = (inactive_alias.get("rider") or {}).get("name") or rider_name
            r_status = (inactive_alias.get("rider") or {}).get("status") or "active"
            # Return update to reactivate
            return inactive_alias["rider_id"], inactive_alias["id"], r_name, r_status, {"id": inactive_alias["id"], "status": "active", "valid_to": None}, None, "MATCHED"

        # Step 5: Name-based match (Pre-fetched riders)
        if rider_name and rider_name.lower() != "unknown":
            norm_name = rider_name.lower().strip()
            # Try exact match first, then partial match in pre-fetched riders
            rider = pre_fetched_riders.get(norm_name)
            if rider:
                rider_id = rider["id"]
                valid_from = f"{payroll_month}-01"
                
                # CRITICAL FIX: Check if this rider already has an active alias on this platform
                # If they do, we MUST deactivate the old one and link the new ID
                existing_active_alias_id = rider_to_active_alias.get(rider_id)
                
                if existing_active_alias_id:
                    # Return an update to deactivate the old one AND a "NEW" instruction for the new ID
                    # Actually, the simplest is to return the NEW alias data
                    # and the system will handle the conflict if we use an upsert or manual deactivation.
                    # For now, let's return it as NEW but flag it for deactivation in Phase 2.
                    new_alias_data = {
                        "rider_id": rider_id,
                        "platform": platform,
                        "platform_rider_id": cleaned_id,
                        "valid_from": valid_from,
                        "valid_to": None,
                        "status": "active",
                        "__deactivate_old_alias_id": existing_active_alias_id # Internal flag
                    }
                else:
                    new_alias_data = {
                        "rider_id": rider_id,
                        "platform": platform,
                        "platform_rider_id": cleaned_id,
                        "valid_from": valid_from,
                        "valid_to": None,
                        "status": "active"
                    }
                return rider_id, "NEW", rider["name"], rider["status"], new_alias_data, None, "MATCHED"

        # Step 6: Failure Case
        error_msg = f"Rider ID {cleaned_id} not found."
        action_item_id = str(uuid.uuid4())
        action_item_data = {
            "id": action_item_id,
            "type": "alias_mismatch",
            "severity": "blocker",
            "responsible_role": "accountant",
            "title": f"Unknown Rider: {rider_name}",
            "subtitle": f"Platform ID {cleaned_id} mismatch.",
            "reference_id": payslip_id,
            "route": f"/alias-resolution/{action_item_id}",
            "argument_id": payslip_id, # Link for convenience
        }
        return None, None, None, error_msg, None, action_item_data, "ERROR"

    except Exception as e:
        return None, None, None, f"System Resolve Error: {str(e)}", None, None, "ERROR"


def prefetch_deductions(rider_ids: list):
    """
    Fetches and aggregates deductions for a list of riders in bulk.
    Returns: {
        rider_id: {
            "total_fines": float,
            "total_expenses": float,
            "other_deductions": float,
            "items": [ {"label": str, "amount": float, "type": str} ]
        }
    }
    """
    deduction_map = {
        rid: {
            "total_fines": 0.0,
            "total_expenses": 0.0,
            "other_deductions": 0.0,
            "items": [],
        } for rid in rider_ids
    }

    if not rider_ids:
        return deduction_map

    rider_id_set = set(rider_ids)

    def _normalize_money(value) -> float:
        try:
            return abs(float(value or 0))
        except Exception:
            return 0.0

    def _clean_label(raw: str, fallback: str) -> str:
        txt = str(raw or "").strip()
        return txt if txt else fallback

    def _append_item(rid: str, label: str, amount_abs: float, item_type: str, subtype: str | None = None, source: str | None = None):
        if rid not in deduction_map or amount_abs <= 0:
            return

        final_label = label.strip() or ("Fine" if item_type == "fine" else "Expense")
        normalized_type = "fine" if item_type == "fine" else "deduction"
        final_subtype = (subtype or "").strip() or None
        final_source = (source or "").strip() or None

        existing = next(
            (
                it
                for it in deduction_map[rid]["items"]
                if it.get("label") == final_label
                and it.get("type") == normalized_type
                and (it.get("subtype") or None) == final_subtype
            ),
            None,
        )
        if existing:
            existing["amount"] = float(existing.get("amount") or 0) - amount_abs
            return

        payload = {
            "label": final_label,
            "amount": -amount_abs,
            "type": normalized_type,
        }
        if final_subtype:
            payload["subtype"] = final_subtype
        if final_source:
            payload["source"] = final_source
        deduction_map[rid]["items"].append(payload)

    # 1. External fines from traffic_fines are always shown under Fine as "Traffic Fine".
    try:
        fines_res = supabase.table("traffic_fines") \
            .select("rider_id, amount, status") \
            .in_("rider_id", rider_ids) \
            .neq("status", "fully_recovered") \
            .execute()

        for row in (fines_res.data or []):
            rid = row.get("rider_id")
            if rid not in deduction_map:
                continue
            amt = _normalize_money(row.get("amount"))
            if amt <= 0:
                continue
            deduction_map[rid]["total_fines"] += amt
            _append_item(rid, "Traffic Fine", amt, "fine", subtype="external_fine", source="traffic_fines")
    except Exception as e:
        print(f"Warning: Bulk traffic fines fetch failed: {e}")

    # 2. Journal categories are the source-of-truth for salary deductions.
    #    fine -> Fine section
    #    expense/loan -> Expense section
    # Performance: query only journals linked to requested riders (chunked),
    # instead of scanning all posted receivable journals globally.
    try:
        journal_rows = []
        seen_journal_ids = set()

        for rider_chunk in _chunk_list(rider_ids, 200):
            if not rider_chunk:
                continue

            direct_res = supabase.table("journals") \
                .select("id, rider_id, receivable_entity_type, receivable_entity_id, receivable_amount, description, type") \
                .eq("status", "posted") \
                .eq("is_receivable", True) \
                .in_("rider_id", rider_chunk) \
                .execute()

            receivable_res = supabase.table("journals") \
                .select("id, rider_id, receivable_entity_type, receivable_entity_id, receivable_amount, description, type") \
                .eq("status", "posted") \
                .eq("is_receivable", True) \
                .eq("receivable_entity_type", "rider") \
                .in_("receivable_entity_id", rider_chunk) \
                .execute()

            for row in (direct_res.data or []):
                jid = row.get("id")
                if jid and jid in seen_journal_ids:
                    continue
                if jid:
                    seen_journal_ids.add(jid)
                journal_rows.append(row)

            for row in (receivable_res.data or []):
                jid = row.get("id")
                if jid and jid in seen_journal_ids:
                    continue
                if jid:
                    seen_journal_ids.add(jid)
                journal_rows.append(row)

        for j in journal_rows:
            candidates = []
            rid_direct = j.get("rider_id")
            if rid_direct:
                candidates.append(rid_direct)

            if j.get("receivable_entity_type") == "rider":
                rid_receivable = j.get("receivable_entity_id")
                if rid_receivable:
                    candidates.append(rid_receivable)

            resolved_candidates = []
            seen = set()
            for c in candidates:
                if c and c in rider_id_set and c not in seen:
                    seen.add(c)
                    resolved_candidates.append(c)

            if len(resolved_candidates) > 1:
                print(f"Warning: Skipping ambiguous receivable journal {j.get('id')}: {resolved_candidates}")
                continue

            rid = resolved_candidates[0] if resolved_candidates else None
            if rid not in deduction_map:
                continue

            # Payroll salary deduction must always come from receivable_amount.
            # Do not fall back to total_amount here.
            amt = _normalize_money(j.get("receivable_amount"))
            if amt <= 0:
                continue

            j_type = str(j.get("type") or "").strip().lower()
            desc = str(j.get("description") or "").strip()

            if j_type == "fine":
                label = _clean_label(desc, "Fine")
                deduction_map[rid]["total_fines"] += amt
                _append_item(rid, label, amt, "fine", subtype="internal_fine", source="journals")
                continue

            if j_type in {"expense", "loan"}:
                label = _clean_label(desc, "Loan Repayment" if j_type == "loan" else "Expense")
                deduction_map[rid]["total_expenses"] += amt
                if j_type == "loan":
                    deduction_map[rid]["other_deductions"] += amt
                _append_item(
                    rid,
                    label,
                    amt,
                    "deduction",
                    subtype=("loan" if j_type == "loan" else "expense"),
                    source="journals",
                )
    except Exception as e:
        print(f"Warning: Bulk journal deductions fetch failed: {e}")

    return deduction_map


def _parse_double_key(row_data, keys):
    """Safety helper to find and parse double values from multiple possible keys."""
    for key in keys:
        if key in row_data and row_data[key] is not None:
            try:
                val_str = str(row_data[key]).replace('AED', '').replace(',', '').strip()
                return float(val_str)
            except (ValueError, TypeError):
                continue
    return 0.0

def _map_payroll_row_data(platform, row_data):
    """Maps platform-specific raw rows to a standard dict of financial values."""
    platform = platform.lower()
    res = {
        "gross_salary": 0.0, "arears": 0.0, "tds_bonus": 0.0, "food_compensation": 0.0,
        "tips": 0.0, "online_hours": 0.0, "order_count": 0,
        "platform_deductions": 0.0, "cod_deficit": 0.0, "clawback_deduction": 0.0,
    }
    
    if platform == "talabat":
        res["gross_salary"] = _parse_double_key(row_data, ["Gross Salary", "Amount", "Total Pay"])
        res["order_count"] = int(_parse_double_key(row_data, ["Total Completed Deliveries", "Deliveries", "Orders"]))
        res["cod_deficit"] = _parse_double_key(row_data, ["COD Deficit"])
        res["clawback_deduction"] = _parse_double_key(row_data, ["Clawback Deduction", "Clawback"])
        res["platform_deductions"] = _parse_double_key(row_data, ["Inventory Deduction", "Platform Deduction"])
        res["arears"] = _parse_double_key(row_data, ["Arears", "Arrears"])
        res["tds_bonus"] = _parse_double_key(row_data, ["TDS Bonus", "TDS"])
        res["tips"] = _parse_double_key(row_data, ["Tips"])
    elif platform == "keeta":
        res["gross_salary"] = _parse_double_key(row_data, ["Total payable amount", "Courier earnings", "Amount"])
        res["food_compensation"] = _parse_double_key(row_data, ["food compensation", "Food Compensation"])
        res["tips"] = _parse_double_key(row_data, ["Tips"])
        res["order_count"] = int(_parse_double_key(row_data, ["Online Days-Valid", "Online Days", "Orders"]))
        res["online_hours"] = _parse_double_key(row_data, ["Daily Onlines Hours-Valid", "Online Hours"])
        res["platform_deductions"] = _parse_double_key(row_data, ["Deduction", "Deductions"])
    
    return res


def _chunk_list(items: list, size: int = 200):
    if size <= 0:
        size = 200
    for i in range(0, len(items), size):
        yield items[i:i + size]


def _bulk_insert_chunked(table_name: str, rows: list[dict], size: int = 200):
    if not rows:
        return
    for chunk in _chunk_list(rows, size):
        supabase.table(table_name).insert(chunk).execute()

@app.post("/payroll/upload")
def upload_payroll(
    request: PayrollUploadRequest
):
    batch_id = None
    unmatched_ids = []
    error_logs = []
    
    # Batch data collections
    payslips_to_insert = []
    action_items_to_insert = []
    alias_updates_to_run = []
    alias_inserts_to_run = []

    # --- ATOMIC WORKFLOW BUFFERS ---
    # We process everything in memory first. No DB writes until Phase 3.
    batch_id = None
    payslips_to_insert = []
    action_items_to_insert = []
    unmatched_ids = []
    error_logs = []
    alias_updates_to_run = []
    alias_inserts_to_run = []
    rider_deactivations = [] # For alias transitions
    skips_to_insert = []     # New table for traceability

    try:
        # 1. Optimized Pre-fetching (READ ONLY)
        print("PREFETCHING: Starting bulk load for payroll...")
        platform_name = request.platform.lower()
        
        def _fetch_platform_aliases():
            return supabase.table("rider_aliases") \
                .select("*, rider:riders(id, name, status)") \
                .eq("platform", platform_name) \
                .execute()

        def _fetch_active_riders():
            return supabase.table("riders").select("id, name, status").eq("status", "active").execute()

        def _fetch_global_aliases():
            return supabase.table("rider_aliases") \
                .select("platform_rider_id, platform, rider_id") \
                .execute()

        # A-D. Fetch independent datasets in parallel.
        with ThreadPoolExecutor(max_workers=3) as pool:
            alias_future = pool.submit(_fetch_platform_aliases)
            rider_future = pool.submit(_fetch_active_riders)
            global_alias_future = pool.submit(_fetch_global_aliases)

            alias_res = alias_future.result()
            rider_res = rider_future.result()
            global_alias_res = global_alias_future.result()
        
        alias_map = {}
        for a in (alias_res.data or []):
            cid = clean_platform_id(a["platform_rider_id"])
            if cid not in alias_map: alias_map[cid] = []
            alias_map[cid].append(a)

        # B. Prefetch All Riders for Name Matching
        rider_map = { (r.get("name") or "").lower().strip(): r for r in (rider_res.data or []) }

        # C. Prefetch Rider -> Active Alias Map
        rider_to_active_alias = {}
        for cid, aliases in alias_map.items():
            for a in aliases:
                if a["status"] == "active" and a["valid_to"] is None:
                    rider_to_active_alias[a["rider_id"]] = a["id"]

        # D. Prefetch GLOBAL Aliases (For silent skip logic)
        # This builds a map of ALL IDs in the DB across ALL platforms
        global_alias_map = {}
        for a in (global_alias_res.data or []):
            cid = clean_platform_id(a["platform_rider_id"])
            # Only store if not already in the main alias_map (current platform)
            if cid not in global_alias_map:
                global_alias_map[cid] = a


        # 2. Phase 1: In-Memory Processing & Mapping
        resolved_data = [] 
        found_rider_ids = set()

        for idx, row in enumerate(request.rows):
            temp_payslip_id = str(uuid.uuid4())
            cleaned_id = clean_platform_id(row.external_id)
            
            rider_name_from_sheet = (row.raw_data.get("Rider Name") or 
                                     row.raw_data.get("Name") or 
                                     row.raw_data.get("rider_name") or "Unknown")

            # Resolve using Optimized Fn (locally)
            # Pass placeholder "PENDING" as batch_id is not yet created.
            rider_id, alias_id, r_name, r_status, al_update, ai_data, res_flag = resolve_rider_alias_optimized(
                row.external_id,
                request.platform,
                rider_name_from_sheet,
                request.month,
                "PENDING_BATCH_ID", 
                temp_payslip_id,
                alias_map,
                rider_map,
                rider_to_active_alias,
                global_alias_map
            )

            if res_flag == "SKIP":
                # SILENT SKIP: Do not add to resolved_data or error lists
                # Record this for traceability in the new slips table
                skips_to_insert.append({
                    "external_id": cleaned_id,
                    "rider_id": rider_id,
                    "rider_name": (row.raw_data.get("Rider Name") or "Unknown"),
                    "sheet_platform": platform_name,
                    "db_platform": r_status.replace("Cross-platform: ", ""), # Extract platform name
                    "reason": "Mismatched Platform"
                })
                continue

            resolved_data.append({
                "idx": idx, "row": row, "payslip_id": temp_payslip_id, "cleaned_id": cleaned_id,
                "rider_id": rider_id, "alias_id": alias_id, "r_name": r_name, "r_status": r_status
            })

            if rider_id:
                found_rider_ids.add(rider_id)
            
            if al_update:
                if alias_id == "NEW":
                    old_id = al_update.pop("__deactivate_old_alias_id", None)
                    if old_id: rider_deactivations.append(old_id)
                    alias_inserts_to_run.append(al_update)
                else:
                    alias_updates_to_run.append(al_update)
            
            if ai_data:
                action_items_to_insert.append(ai_data)

        # 4. Prefetch Deductions for all found riders in one go
        deductions_map = prefetch_deductions(list(found_rider_ids))


        # 4. Phase 2: Complete Memory Mapping
        for item in resolved_data:
            idx, row, payslip_id, cleaned_id = item["idx"], item["row"], item["payslip_id"], item["cleaned_id"]
            rider_id, alias_id, r_name, r_status = item["rider_id"], item["alias_id"], item["r_name"], item["r_status"]

            fin_res = _map_payroll_row_data(request.platform, row.raw_data)
            base_slip = {
                "id": payslip_id, "external_id": cleaned_id,
                "platform_data": row.raw_data, **fin_res
            }

            if not rider_id:
                # Unresolved
                payslips_to_insert.append({
                    **base_slip, "rider_id": None, "rider_alias_id": None,
                    "rider_name": (row.raw_data.get("Rider Name") or "Unknown"),
                    "status": "error", "error_reason": r_status,
                    "total_fines": float(fin_res.get("platform_deductions") or 0.0),
                    "total_expenses": 0.0, "net_salary": float(fin_res.get("gross_salary") or 0.0),
                    "items": []
                })
                unmatched_ids.append(cleaned_id)
                error_logs.append(f"Row {idx+1}: {r_status}")
                continue

            if r_status == "retired":
                payslips_to_insert.append({
                    **base_slip, "rider_id": rider_id, "rider_alias_id": alias_id if alias_id != "NEW" else None,
                    "rider_name": r_name, "status": "error", "error_reason": "Rider is retired.",
                    "total_fines": float(fin_res.get("platform_deductions") or 0.0),
                    "total_expenses": 0.0, "net_salary": 0.0,
                    "items": []
                })
                unmatched_ids.append(cleaned_id)
                error_logs.append(f"Row {idx+1}: Rider is retired.")
                continue

            # Calculate Net Salary and Items Breakdown
            d = deductions_map.get(rider_id, {"total_fines": 0.0, "total_expenses": 0.0, "items": []})
            
            # Start items breakdown
            items = []
            
            # A. Earnings (Positive amounts)
            if fin_res["gross_salary"] > 0:
                items.append({"label": "Basic Gross", "amount": fin_res["gross_salary"], "type": "earning"})
            if fin_res["arears"] > 0:
                items.append({"label": "Arrears", "amount": fin_res["arears"], "type": "earning"})
            if fin_res["tips"] > 0:
                items.append({"label": "Tips", "amount": fin_res["tips"], "type": "earning"})
            if fin_res["tds_bonus"] > 0:
                items.append({"label": "Bonus/TDS", "amount": fin_res["tds_bonus"], "type": "earning"})
            if fin_res["food_compensation"] > 0:
                items.append({"label": "Food Comp", "amount": fin_res["food_compensation"], "type": "earning"})

            # B. Database-based Deductions (Items are already negative from prefetch)
            db_deductions = list(d.get("items", []))
            items.extend(db_deductions)
            
            # C. Platform-level deductions from Excel (Keep protected during sync)
            if fin_res["platform_deductions"] > 0:
                items.append({"label": "Inventory/Platform Deduction", "amount": -fin_res["platform_deductions"], "type": "platform_deduction"})
            if fin_res["cod_deficit"] > 0:
                items.append({"label": "COD Deficit", "amount": -fin_res["cod_deficit"], "type": "platform_deduction"})
            if fin_res["clawback_deduction"] > 0:
                items.append({"label": "Clawback Deduction", "amount": -fin_res["clawback_deduction"], "type": "platform_deduction"})

            # D. Consistent Net Salary Calculation
            items = [it for it in items if abs(float(it.get("amount") or 0)) > 0.0001]
            net = sum(it["amount"] for it in items)

            fines, expenses = d["total_fines"], d["total_expenses"]

            payslips_to_insert.append({
                **base_slip, "rider_id": rider_id, "rider_alias_id": alias_id if alias_id != "NEW" else None,
                "rider_name": r_name, 
                "total_fines": fines,
                "total_expenses": expenses, 
                "net_salary": net, 
                "status": "matched",
                "items": items
            })

        # --- Phase 3: ATOMIC COMMIT PHASE ---
        print(f"COMMIT: Saving batch {request.month} for {platform_name}...")

        # Attach review metadata (non-blocking at upload time, blocking at finalization time).
        for p in payslips_to_insert:
            p.update(build_payslip_review_meta(p))

        # A. Create Batch (Draft) with calculated total
        total_batch_amount = sum(p["net_salary"] for p in payslips_to_insert)
        
        batch_res = supabase.table("payroll_batches").insert({
            "month": request.month, 
            "platform": str(request.platform), 
            "status": "draft",
            "total_amount": total_batch_amount
        }).execute()
        if not batch_res.data: raise Exception("Initialize batch record failed.")
        batch_id = batch_res.data[0]["id"]

        # B. Bulk Sync Rider Aliases
        if rider_deactivations:
            rider_deactivations = list(set(rider_deactivations))
            supabase.table("rider_aliases")\
                .update({"status": "inactive", "valid_to": datetime.now().isoformat()})\
                .in_("id", rider_deactivations).execute()

        if alias_inserts_to_run:
            alias_payloads = []
            for alias in alias_inserts_to_run:
                payload = dict(alias)
                payload.pop("__deactivate_old_alias_id", None)
                alias_payloads.append(payload)

            res_new_aliases = []
            for chunk in _chunk_list(alias_payloads, 200):
                chunk_res = supabase.table("rider_aliases").insert(chunk).execute()
                if chunk_res.data:
                    res_new_aliases.extend(chunk_res.data)

            new_id_lookup = {
                clean_platform_id(na["platform_rider_id"]): na["id"]
                for na in (res_new_aliases or [])
            }
            for p in payslips_to_insert:
                if p["rider_id"] and p["rider_alias_id"] is None:
                    p["rider_alias_id"] = new_id_lookup.get(clean_platform_id(p["external_id"]))

        if alias_updates_to_run:
            merged_updates = {}
            for upd in alias_updates_to_run:
                upd_id = upd.get("id")
                if not upd_id:
                    continue
                if upd_id not in merged_updates:
                    merged_updates[upd_id] = {"id": upd_id}
                for k, v in upd.items():
                    if k != "id":
                        merged_updates[upd_id][k] = v

            update_rows = list(merged_updates.values())
            if update_rows:
                for chunk in _chunk_list(update_rows, 200):
                    supabase.table("rider_aliases").upsert(chunk).execute()

        # C. Insert Linked Payslips & Action Items
        for p in payslips_to_insert: p["batch_id"] = batch_id
        if payslips_to_insert:
            _bulk_insert_chunked("payslips", payslips_to_insert, 200)
        
        if action_items_to_insert:
            _bulk_insert_chunked("action_items", action_items_to_insert, 200)

        # D. Insert Skips for traceability
        if skips_to_insert:
            for s in skips_to_insert: s["batch_id"] = batch_id
            print(f"TRACE: Recording {len(skips_to_insert)} skipped riders for batch {batch_id}")
            _bulk_insert_chunked("payroll_skips", skips_to_insert, 200)

        return {
            "batch_id": batch_id,
            "message": f"Processed {len(payslips_to_insert) - len(error_logs)} successful payslips and {len(error_logs)} errors.",
            "status": "draft",
            "payslips_created": len(payslips_to_insert),
            "unmatched_ids": unmatched_ids,
            "error_logs": error_logs
        }

    except Exception as e:
        print(f"ATOMIC ROLLBACK: {e}")
        if batch_id:
            try:
                print(f"CLEANING: Removing failed batch {batch_id}...")
                supabase.table("payslips").delete().eq("batch_id", batch_id).execute()
                supabase.table("payroll_batches").delete().eq("id", batch_id).execute()
            except Exception as cleanup_err:
                print(f"Rollback failed: {cleanup_err}")
                
        raise HTTPException(status_code=500, detail=f"Critical system failure during upload: {str(e)}")


@app.post("/payroll/upload/async")
def upload_payroll_async(
    request: PayrollUploadRequest,
    background_tasks: BackgroundTasks,
):
    """
    Backward-compatible async upload path.
    Returns immediately with a job_id while processing happens in background.
    """
    job_id = str(uuid.uuid4())
    payload = request.model_dump()

    _set_upload_job(
        job_id,
        {
            "job_id": job_id,
            "status": "queued",
            "progress": 0,
            "stage": "queued",
            "created_at": datetime.now().isoformat(),
            "request_meta": {
                "month": request.month,
                "platform": request.platform,
                "rows_count": len(request.rows or []),
            },
            "result": None,
            "error": None,
        },
    )

    background_tasks.add_task(_run_payroll_upload_job, job_id, payload)

    return {
        "job_id": job_id,
        "status": "queued",
        "message": "Payroll upload queued for background processing",
    }


@app.get("/payroll/upload/status/{job_id}")
def get_payroll_upload_status(job_id: str):
    with PAYROLL_UPLOAD_JOBS_LOCK:
        job = PAYROLL_UPLOAD_JOBS.get(job_id)

    if not job:
        raise HTTPException(status_code=404, detail="Upload job not found")

    return job


@app.post("/payroll/sync/batch/{batch_id}")
def sync_payroll_batch(batch_id: str):
    """
    Dynamic Sync Logic:
    Refreshes all payslips in a DRAFT batch by re-fetching database-based deductions 
    (fines, expenses, loans) while keeping the original Excel data intact.
    """
    try:
        # 1. Verify Batch Status
        batch_res = supabase.table("payroll_batches").select("*").eq("id", batch_id).single().execute()
        if not batch_res.data:
            raise HTTPException(status_code=404, detail="Batch not found")
        
        batch = batch_res.data
        if batch["status"] not in ["draft", "error"]:
            raise HTTPException(status_code=400, detail=f"Cannot sync batch in {batch['status']} status.")

        # 2. Fetch all payslips for this batch
        slips_res = supabase.table("payslips").select("*").eq("batch_id", batch_id).execute()
        slips = slips_res.data or []
        
        if not slips:
            return {"message": "No payslips found in this batch.", "updated_count": 0}

        # Filter out slips that don't have a rider_id (can't sync them)
        syncable_slips = [s for s in slips if s.get("rider_id")]
        rider_ids = list(set(s["rider_id"] for s in syncable_slips))

        print(f"SYNC: Refreshing {len(syncable_slips)} payslips for batch {batch_id}...")

        # 3. Bulk Fetch Fresh Deductions
        fresh_deductions_map = prefetch_deductions(rider_ids)

        # 4. Process each slip in memory
        updated_slips = []
        for slip in syncable_slips:
            rider_id = slip["rider_id"]
            d = fresh_deductions_map.get(rider_id)
            if not d: continue

            # Keep Excel-based items: 'earning' and 'platform_deduction'
            old_items = slip.get("items") or []
            excel_items = [i for i in old_items if i.get("type") in ["earning", "platform_deduction"]]
            
            # Get fresh DB items: 'fine' and 'deduction'
            new_db_items = d.get("items") or []
            
            # Merge
            merged_items = excel_items + new_db_items
            merged_items = [it for it in merged_items if abs(float(it.get("amount") or 0)) > 0.0001]
            
            # Recalculate totals
            new_net = sum(it["amount"] for it in merged_items)
            
            # Update slip record
            updated_payload = {
                "id": slip["id"],
                "rider_id": rider_id,
                "status": slip.get("status", "matched"),
                "items": merged_items,
                "net_salary": new_net,
                "total_fines": d["total_fines"],
                "total_expenses": d["total_expenses"],
                "other_deductions": d["other_deductions"]
            }

            review_meta = build_payslip_review_meta(updated_payload)

            # Preserve immutable adjustment/carry-forward audit trail during sync.
            existing_snapshot = slip.get("issue_snapshot")
            existing_snapshot = existing_snapshot if isinstance(existing_snapshot, dict) else {}
            merged_snapshot = dict(review_meta.get("issue_snapshot") or {})

            existing_history = existing_snapshot.get("adjustment_history")
            if isinstance(existing_history, list) and existing_history:
                merged_snapshot["adjustment_history"] = existing_history[-1000:]

            existing_last_adjustment = existing_snapshot.get("last_adjustment")
            if isinstance(existing_last_adjustment, dict) and existing_last_adjustment:
                merged_snapshot["last_adjustment"] = existing_last_adjustment

            existing_decisions = existing_snapshot.get("carry_forward_decisions")
            if isinstance(existing_decisions, list) and existing_decisions:
                merged_snapshot["carry_forward_decisions"] = existing_decisions[-2000:]

            review_meta["issue_snapshot"] = merged_snapshot
            updated_payload.update(review_meta)
            updated_slips.append(updated_payload)

        # 5. Bulk Update Payslips
        if updated_slips:
            # Postgrest doesn't support easy bulk update by ID easily in one call 
            # with different values. We'll upsert them or loop. Upsert is safer.
            supabase.table("payslips").upsert(updated_slips).execute()

        # 6. Finally, update the batch total amount
        new_batch_total = sum(s["net_salary"] for s in updated_slips)
        # (Need to account for non-syncable slips if they have net salary)
        non_syncable_total = sum(s["net_salary"] for s in slips if not s.get("rider_id"))
        
        final_total = new_batch_total + non_syncable_total
        
        supabase.table("payroll_batches").update({"total_amount": final_total}).eq("id", batch_id).execute()

        return {
            "message": f"Successfully synced {len(updated_slips)} payslips.",
            "updated_count": len(updated_slips),
            "new_total": final_total
        }

    except Exception as e:
        print(f"SYNC ERROR: {e}")
        raise HTTPException(status_code=500, detail=f"Sync failed: {str(e)}")


@app.post("/payroll/batch/{batch_id}/finalize")
def finalize_payroll(
    batch_id: str,
    data: PayrollFinalizeRequest,
    user = Depends(require_role("ACCOUNTANT"))
):
    """
    Finalizes a payroll batch:
    1. Validates no 'mismatch' payslips exist.
    2. Validates no 'unmatched' fines exist for any rider in batch.
    3. Checks drawer balance.
    4. Creates and posts journals for each payslip.
    5. Updates batch status to 'finalized'.
    """
    try:
        # 1. Fetch Batch
        batch_res = supabase.table("payroll_batches").select("*").eq("id", batch_id).single().execute()
        if not batch_res.data:
            raise HTTPException(status_code=404, detail="Batch not found")
        batch = batch_res.data
        if batch["status"] == "finalized":
            return {"message": "Batch already finalized"}

        # 2. Fetch Payslips
        payslips_res = supabase.table("payslips").select("*").eq("batch_id", batch_id).execute()
        payslips = payslips_res.data or []
        if not payslips:
            raise HTTPException(status_code=400, detail="Batch has no payslips to finalize")

        # Finalize only remaining payslips (supports partial one-by-one finalization).
        pending_payslips = [p for p in payslips if str(p.get("status") or "").lower() != "finalized"]
        if not pending_payslips:
            # Keep batch status consistent even if everything was finalized individually.
            if str(batch.get("status") or "").lower() != "finalized":
                supabase.table("payroll_batches") \
                    .update({"status": "finalized"}) \
                    .eq("id", batch_id) \
                    .execute()
            return {"message": "Batch already finalized", "total_net": 0.0, "payslips_processed": 0}

        # 3. Check for Blocker: Mismatched Payslips
        mismatched = [p for p in pending_payslips if p.get("status") == "mismatch"]
        if mismatched:
            raise HTTPException(
                status_code=400, 
                detail=f"Cannot finalize batch. {len(mismatched)} payslips have status 'mismatch'. Fix aliases or remove retired riders first."
            )

        non_payable = [
            p for p in pending_payslips
            if str(p.get("status") or "").lower() != "matched"
        ]
        if non_payable:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Cannot finalize batch. {len(non_payable)} payslips are not ready for payment "
                    f"(status must be 'matched')."
                ),
            )

        flagged_for_review = [p for p in pending_payslips if p.get("review_required")]
        if flagged_for_review:
            sample = flagged_for_review[0]
            sample_codes = ", ".join(sample.get("issue_codes") or [])
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Cannot finalize batch. {len(flagged_for_review)} payslips are flagged for review. "
                    f"Example rider: {sample.get('rider_name', 'Unknown')} (issues: {sample_codes or 'unknown'})."
                ),
            )

        # 4. Check for Blocker: Unmatched Fines for riders in this batch
        rider_ids = list({p["rider_id"] for p in pending_payslips if p["rider_id"]})
        unmatched_fines_res = supabase.table("traffic_fines") \
            .select("id, ticket_number, rider_name") \
            .eq("status", "unmatched") \
            .in_("rider_id", rider_ids) \
            .execute()
        
        if unmatched_fines_res.data:
            fines_count = len(unmatched_fines_res.data)
            sample_fine = unmatched_fines_res.data[0]
            raise HTTPException(
                status_code=400,
                detail=f"BLOCKER: {fines_count} unmatched fines detected for riders in this batch. (e.g. {sample_fine['ticket_number']} for {sample_fine['rider_name']}). All fines must be matched, assigned, or fully recovered before finalization."
            )

        # 5. Check Drawer Balance
        total_net = sum(float(p["net_salary"]) for p in pending_payslips)
        drawer_res = supabase.table("drawer").select("balance, name").eq("id", data.drawer_id).single().execute()
        if not drawer_res.data:
            raise HTTPException(status_code=404, detail="Selected drawer not found")
        
        current_balance = float(drawer_res.data["balance"])
        if current_balance < total_net:
            raise HTTPException(
                status_code=400,
                detail=f"Insufficient funds in {drawer_res.data['name']}. Required: AED {total_net:.2f}, Available: AED {current_balance:.2f}"
            )

        # 6. Create Journals and Post in Bulk
        journals_to_insert = []
        lines_to_insert = []
        journal_ids_to_post = []

        drawer_account_id = "CASH-BANK"
        drawer_name = (drawer_res.data.get("name") or "").strip().lower()
        if drawer_name == "cash":
            drawer_account_id = "CASH-MAIN"
        elif drawer_name == "noqodi":
            drawer_account_id = "CASH-NOQODI"
        
        for p in pending_payslips:
            rider_id = p.get("rider_id")
            rider_name = p.get("rider_name") or "Unknown Rider"
            gross_salary = float(p.get("gross_salary") or 0)
            net_salary = float(p.get("net_salary") or 0)
            deduction_amount = max(0.0, gross_salary - net_salary)
            entry_date = datetime.now().strftime("%Y-%m-%d")

            gross_journal_id = str(uuid.uuid4())
            journals_to_insert.append({
                "id": gross_journal_id,
                "entry_date": entry_date,
                "description": f"Salary Accrual (Gross): {batch['month']} - {rider_name}",
                "total_amount": gross_salary,
                "status": "draft",
                "type": "salary",
                "created_by_user_id": user["id"],
                "created_by_role": "accountant",
                "party_type": "rider",
                "party_id": rider_id,
                "receivable_entity_type": "rider",
                "receivable_entity_id": rider_id,
                "source_document_ref": f"payslip:{p.get('id')}",
            })
            journal_ids_to_post.append(gross_journal_id)

            lines_to_insert.extend([
                {
                    "journal_id": gross_journal_id,
                    "account_id": "salary_expense",
                    "debit_amount": gross_salary,
                    "credit_amount": 0,
                    "drawer_id": None,
                    "party_type": "rider",
                    "party_id": rider_id,
                },
                {
                    "journal_id": gross_journal_id,
                    "account_id": "salary_payable",
                    "debit_amount": 0,
                    "credit_amount": gross_salary,
                    "drawer_id": None,
                    "party_type": "rider",
                    "party_id": rider_id,
                },
            ])

            if deduction_amount > 0:
                deduction_journal_id = str(uuid.uuid4())
                journals_to_insert.append({
                    "id": deduction_journal_id,
                    "entry_date": entry_date,
                    "description": f"Salary Deduction Applied: {batch['month']} - {rider_name}",
                    "total_amount": deduction_amount,
                    "status": "draft",
                    "type": "salary",
                    "created_by_user_id": user["id"],
                    "created_by_role": "accountant",
                    "party_type": "rider",
                    "party_id": rider_id,
                    "receivable_entity_type": "rider",
                    "receivable_entity_id": rider_id,
                    "source_document_ref": f"payslip:{p.get('id')}",
                })
                journal_ids_to_post.append(deduction_journal_id)

                lines_to_insert.extend([
                    {
                        "journal_id": deduction_journal_id,
                        "account_id": "salary_payable",
                        "debit_amount": deduction_amount,
                        "credit_amount": 0,
                        "drawer_id": None,
                        "party_type": "rider",
                        "party_id": rider_id,
                    },
                    {
                        "journal_id": deduction_journal_id,
                        "account_id": "expense_receivable",
                        "debit_amount": 0,
                        "credit_amount": deduction_amount,
                        "drawer_id": None,
                        "party_type": "rider",
                        "party_id": rider_id,
                    },
                ])

            net_journal_id = str(uuid.uuid4())
            journals_to_insert.append({
                "id": net_journal_id,
                "entry_date": entry_date,
                "description": f"Net Salary Payment: {batch['month']} - {rider_name}",
                "total_amount": net_salary,
                "status": "draft",
                "type": "salary",
                "created_by_user_id": user["id"],
                "created_by_role": "accountant",
                "payment_method": data.payment_method,
                "drawer_id": data.drawer_id,
                "party_type": "rider",
                "party_id": rider_id,
                "receivable_entity_type": "rider",
                "receivable_entity_id": rider_id,
                "source_document_ref": f"payslip:{p.get('id')}",
            })
            journal_ids_to_post.append(net_journal_id)

            lines_to_insert.extend([
                {
                    "journal_id": net_journal_id,
                    "account_id": "salary_payable",
                    "debit_amount": net_salary,
                    "credit_amount": 0,
                    "drawer_id": None,
                    "party_type": "rider",
                    "party_id": rider_id,
                },
                {
                    "journal_id": net_journal_id,
                    "account_id": drawer_account_id,
                    "debit_amount": 0,
                    "credit_amount": net_salary,
                    "drawer_id": data.drawer_id,
                    "party_type": "rider",
                    "party_id": rider_id,
                },
            ])

        if journals_to_insert:
            print(f"POSTING: Finalizing {len(journals_to_insert)} journals...")
            _bulk_insert_chunked("journals", journals_to_insert, 200)
            _bulk_insert_chunked("journal_lines", lines_to_insert, 400)

            # Critical: trigger the same draft -> posted transition used by
            # individual finalize flow so ledger entries are created reliably.
            supabase.table("journals") \
                .update({
                    "status": "posted",
                    "approved_by": user["id"],
                    "approved_at": datetime.now().isoformat(),
                }) \
                .in_("id", journal_ids_to_post) \
                .execute()

            # Mark processed payslips finalized so they are not posted again.
            pending_ids = [p.get("id") for p in pending_payslips if p.get("id")]
            if pending_ids:
                supabase.table("payslips") \
                    .update({"status": "finalized"}) \
                    .in_("id", pending_ids) \
                    .execute()
            
            # Update payslip with journal reference
            # Note: Need to check if payslips table has journal_id. Or just rely on journals table link.
            # SRS/Schema check: payslips table doesn't have journal_id column in my previous view, 
            # but journals has receivable_entity_id.

        # 7. Update Batch Status
        supabase.table("payroll_batches") \
            .update({"status": "finalized"}) \
            .eq("id", batch_id) \
            .execute()

        # 8. Update Drawer Balance
        supabase.table("drawer") \
            .update({"balance": current_balance - total_net}) \
            .eq("id", data.drawer_id) \
            .execute()

        return {
            "message": "Payroll finalized successfully",
            "total_net": total_net,
            "payslips_processed": len(pending_payslips),
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"Finalization Error: {e}")
        raise HTTPException(status_code=500, detail=f"Finalization failed: {str(e)}")


@app.get("/payroll/history")
async def get_payroll_history():
    try:
        # Fetch batches with their payslip counts
        response = supabase.table("payroll_batches").select("*, payslips(id)").order("created_at", desc=True).execute()
        
        # Filter out batches that have no payslips
        valid_batches = []
        for batch in response.data or []:
            if batch.get("payslips") and len(batch["payslips"]) > 0:
                # Remove the payslips detail from the batch object to keep response small
                batch.pop("payslips", None)
                valid_batches.append(batch)
                
        return {"batches": valid_batches}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/payroll/batch/{batch_id}/payslips")
async def get_payslips_for_batch_alias(batch_id: str):
    try:
        # Get batch info
        batch_res = supabase.table("payroll_batches").select("*").eq("id", batch_id).execute()
        batch_info = batch_res.data[0] if batch_res.data else None
        
        # Join with riders and rider_aliases to get rider info
        response = supabase.table("payslips").select("*, riders(name), rider_aliases(platform, platform_rider_id)").eq("batch_id", batch_id).execute()
        return {
            "payslips": response.data,
            "batch": batch_info
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/payroll/payslip/{payslip_id}/deductions")
def get_grouped_payslip_deductions(
    payslip_id: str,
    user=Depends(require_role(["ACCOUNTANT", "PRO"])),
):
    """
    Returns grouped deductions for payslip UI rendering:
    - Fines: internal/external/total
    - Expenses: category lines + total
    """
    try:
        res = supabase.table("payslips") \
            .select("id, rider_id, rider_name, status, items, net_salary, total_fines, total_expenses") \
            .eq("id", payslip_id) \
            .single() \
            .execute()

        payslip = res.data
        if not payslip:
            raise HTTPException(status_code=404, detail="Payslip not found")

        grouped = group_payslip_deductions(payslip.get("items") or [])

        return {
            "payslip_id": payslip["id"],
            "rider_id": payslip.get("rider_id"),
            "rider_name": payslip.get("rider_name"),
            "status": payslip.get("status"),
            "net_salary": float(payslip.get("net_salary") or 0),
            "deductions": grouped,
            "legacy_totals": {
                "total_fines": float(payslip.get("total_fines") or 0),
                "total_expenses": float(payslip.get("total_expenses") or 0),
            },
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get grouped deductions: {str(e)}")


@app.get("/payroll/batch/{batch_id}/flagged-payslips")
def get_flagged_payslips_for_batch(
    batch_id: str,
    user=Depends(require_role("ACCOUNTANT")),
):
    """Return only payslips that require review for fast accountant triage."""
    try:
        res = supabase.table("payslips") \
            .select("id, rider_id, rider_name, external_id, status, net_salary, review_required, issue_codes, issue_snapshot") \
            .eq("batch_id", batch_id) \
            .eq("review_required", True) \
            .execute()

        flagged = res.data or []
        return {
            "batch_id": batch_id,
            "flagged_count": len(flagged),
            "flagged_payslips": flagged,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch flagged payslips: {str(e)}")


@app.get("/payroll/batch/{batch_id}/review-summary")
def get_batch_review_summary(
    batch_id: str,
    user=Depends(require_role("ACCOUNTANT")),
):
    """
    Summarize whether a batch is finalization-ready.
    Keeps existing flow untouched; this is read-only support for UI and operations.
    """
    try:
        slips_res = supabase.table("payslips") \
            .select("id, status, net_salary, review_required, issue_codes") \
            .eq("batch_id", batch_id) \
            .execute()

        slips = slips_res.data or []
        total = len(slips)
        flagged = [s for s in slips if s.get("review_required")]
        mismatched = [s for s in slips if str(s.get("status") or "").lower() == "mismatch"]
        negative_net = [
            s for s in slips
            if float(s.get("net_salary") or 0) < 0
        ]

        issue_counts: dict[str, int] = {}
        for s in flagged:
            for code in (s.get("issue_codes") or []):
                issue_counts[code] = int(issue_counts.get(code) or 0) + 1

        ready_to_finalize = total > 0 and len(flagged) == 0 and len(mismatched) == 0

        return {
            "batch_id": batch_id,
            "total_payslips": total,
            "flagged_count": len(flagged),
            "mismatch_count": len(mismatched),
            "negative_net_count": len(negative_net),
            "issue_counts": issue_counts,
            "ready_to_finalize": ready_to_finalize,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to build review summary: {str(e)}")


@app.patch("/payroll/payslip/{payslip_id}/deduction")
def edit_payslip_deduction_item(
    payslip_id: str,
    data: PayslipDeductionEditRequest,
    user=Depends(require_role("ACCOUNTANT")),
):
    """
    Accountant-only safe edit for a single deduction item.
    Integrity guards:
    - Only draft/error batches can be edited
    - Finalized payslips are immutable
    - Only deduction/fine/platform_deduction items can be edited
    - Totals + flags are recalculated server-side
    """
    try:
        if data.item_index < 0:
            raise HTTPException(status_code=400, detail="item_index must be >= 0")

        if data.new_amount < 0:
            raise HTTPException(status_code=400, detail="new_amount must be >= 0")

        payslip_res = supabase.table("payslips") \
            .select("*") \
            .eq("id", payslip_id) \
            .single() \
            .execute()

        payslip = payslip_res.data
        if not payslip:
            raise HTTPException(status_code=404, detail="Payslip not found")

        if str(payslip.get("status") or "").lower() == "finalized":
            raise HTTPException(status_code=400, detail="Finalized payslip cannot be edited")

        batch_id = payslip.get("batch_id")
        if not batch_id:
            raise HTTPException(status_code=400, detail="Payslip has no batch_id")

        batch_res = supabase.table("payroll_batches") \
            .select("status") \
            .eq("id", batch_id) \
            .single() \
            .execute()

        batch = batch_res.data or {}
        if str(batch.get("status") or "").lower() not in ["draft", "error"]:
            raise HTTPException(status_code=400, detail="Only draft/error batches can be edited")

        items = payslip.get("items") or []
        if data.item_index >= len(items):
            raise HTTPException(status_code=400, detail="item_index out of range")

        target = dict(items[data.item_index])
        target_type = str(target.get("type") or "").lower()
        editable_types = {"deduction", "fine", "platform_deduction"}
        if target_type not in editable_types:
            raise HTTPException(
                status_code=400,
                detail=f"Item type '{target_type}' is not editable. Only deduction/fine/platform_deduction are editable.",
            )

        if data.expected_label:
            current_label = str(target.get("label") or "")
            if current_label.strip() != data.expected_label.strip():
                raise HTTPException(
                    status_code=409,
                    detail=f"Label mismatch. Expected '{data.expected_label}', found '{current_label}'. Refresh and retry.",
                )

        old_amount = float(target.get("amount") or 0)

        target["original_amount"] = float(target.get("original_amount") or old_amount)
        target["amount"] = -abs(float(data.new_amount))
        target["is_adjusted"] = True
        target["manual_override"] = True
        if data.reason:
            target["adjustment_reason"] = data.reason

        old_items_snapshot = [dict(it) for it in items]
        items[data.item_index] = target

        calc = recalc_payslip_totals_from_items(items)

        review_meta = build_payslip_review_meta({
            "status": payslip.get("status"),
            "rider_id": payslip.get("rider_id"),
            "net_salary": calc["net_salary"],
        })

        issue_snapshot = payslip.get("issue_snapshot")
        issue_snapshot = issue_snapshot if isinstance(issue_snapshot, dict) else {}
        history = issue_snapshot.get("adjustment_history")
        history = history if isinstance(history, list) else []

        new_history_entries = build_adjustment_history_entries(
            old_items_snapshot,
            calc["items"],
            user["id"],
            data.reason or "UI adjustment",
        )
        history.extend(new_history_entries)
        issue_snapshot["adjustment_history"] = history[-1000:]
        issue_snapshot["last_adjustment"] = {
            "item_index": data.item_index,
            "label": target.get("label"),
            "old_amount": old_amount,
            "new_amount": target["amount"],
            "reason": data.reason or "",
            "adjusted_by": user["id"],
            "adjusted_at": datetime.now().isoformat(),
        }

        update_payload = {
            "items": calc["items"],
            "net_salary": calc["net_salary"],
            "total_fines": calc["total_fines"],
            "total_expenses": calc["total_expenses"],
            "other_deductions": calc["other_deductions"],
            "review_required": review_meta["review_required"],
            "issue_codes": review_meta["issue_codes"],
            "issue_snapshot": issue_snapshot,
            "adjusted_by": user["id"],
            "adjusted_at": datetime.now().isoformat(),
        }

        updated_res = supabase.table("payslips") \
            .update(update_payload) \
            .eq("id", payslip_id) \
            .execute()

        updated_row = updated_res.data[0] if updated_res.data else None

        return {
            "message": "Payslip deduction updated successfully",
            "payslip": updated_row,
            "recalculated": {
                "net_salary": calc["net_salary"],
                "total_fines": calc["total_fines"],
                "total_expenses": calc["total_expenses"],
                "review_required": review_meta["review_required"],
                "issue_codes": review_meta["issue_codes"],
            },
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to edit payslip deduction: {str(e)}")


@app.patch("/payroll/payslip/{payslip_id}/items")
def replace_payslip_items(
    payslip_id: str,
    data: PayslipItemsReplaceRequest,
    user=Depends(require_role("ACCOUNTANT")),
):
    """
    Replace payslip items in draft/error state and recalculate everything server-side.
    Supports add/update/remove flows while preserving integrity and history.
    """
    try:
        payslip_res = supabase.table("payslips") \
            .select("*") \
            .eq("id", payslip_id) \
            .single() \
            .execute()
        payslip = payslip_res.data
        if not payslip:
            raise HTTPException(status_code=404, detail="Payslip not found")

        if str(payslip.get("status") or "").lower() == "finalized":
            raise HTTPException(status_code=400, detail="Finalized payslip cannot be edited")

        batch_id = payslip.get("batch_id")
        batch_res = supabase.table("payroll_batches") \
            .select("status") \
            .eq("id", batch_id) \
            .single() \
            .execute()
        batch = batch_res.data or {}
        if str(batch.get("status") or "").lower() not in ["draft", "error"]:
            raise HTTPException(status_code=400, detail="Only draft/error batches can be edited")

        old_items = payslip.get("items") or []

        # Normalize signs to preserve accounting semantics.
        normalized: list[dict] = []
        for raw in data.items or []:
            item = dict(raw)
            try:
                amt = float(item.get("amount") or 0)
            except Exception:
                amt = 0.0

            item_type = str(item.get("type") or "").lower().strip()
            if item_type == "earning":
                item["amount"] = abs(amt)
            elif item_type in {"deduction", "fine", "platform_deduction"}:
                item["amount"] = -abs(amt)
            else:
                # Unknown types are dropped for safety.
                continue

            normalized.append(item)

        calc = recalc_payslip_totals_from_items(normalized)
        review_meta = build_payslip_review_meta({
            "status": payslip.get("status"),
            "rider_id": payslip.get("rider_id"),
            "net_salary": calc["net_salary"],
        })

        issue_snapshot = payslip.get("issue_snapshot")
        issue_snapshot = issue_snapshot if isinstance(issue_snapshot, dict) else {}
        history = issue_snapshot.get("adjustment_history")
        history = history if isinstance(history, list) else []
        history_entries = build_adjustment_history_entries(
            [dict(it) for it in old_items],
            calc["items"],
            user["id"],
            data.reason or "UI adjustment",
        )
        history.extend(history_entries)
        issue_snapshot["adjustment_history"] = history[-1000:]
        if history_entries:
            issue_snapshot["last_adjustment"] = history_entries[-1]

        payload = {
            "items": calc["items"],
            "net_salary": calc["net_salary"],
            "total_fines": calc["total_fines"],
            "total_expenses": calc["total_expenses"],
            "other_deductions": calc["other_deductions"],
            "review_required": review_meta["review_required"],
            "issue_codes": review_meta["issue_codes"],
            "issue_snapshot": issue_snapshot,
            "adjusted_by": user["id"],
            "adjusted_at": datetime.now().isoformat(),
        }

        upd = supabase.table("payslips") \
            .update(payload) \
            .eq("id", payslip_id) \
            .execute()

        return {
            "message": "Payslip items updated",
            "payslip": upd.data[0] if upd.data else None,
            "history_entries_added": len(history_entries),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to replace payslip items: {str(e)}")


@app.get("/payroll/rider/{rider_id}/carry-forward-options")
def get_rider_carry_forward_options(
    rider_id: str,
    user=Depends(require_role("ACCOUNTANT")),
):
    """
    Build carry-forward suggestions strictly from historical adjustment history.
    Returns reduced amounts that accountant may reapply next cycle.
    """
    try:
        res = supabase.table("payslips") \
            .select("id, batch_id, rider_name, issue_snapshot, items, created_at") \
            .eq("rider_id", rider_id) \
            .order("created_at", desc=True) \
            .execute()

        slips = res.data or []
        options: list[dict] = []

        for slip in slips:
            snap = slip.get("issue_snapshot")
            snap = snap if isinstance(snap, dict) else {}

            history = snap.get("adjustment_history")
            history = history if isinstance(history, list) else []

            decisions = snap.get("carry_forward_decisions")
            decisions = decisions if isinstance(decisions, list) else []
            decided_entry_ids = {str(d.get("entry_id")) for d in decisions if d.get("entry_id")}

            for h in history:
                if not isinstance(h, dict):
                    continue
                entry_id = str(h.get("entry_id") or "")
                reduced_amount = float(h.get("reduced_amount") or 0)
                if not entry_id or reduced_amount <= 0:
                    continue
                if entry_id in decided_entry_ids:
                    continue

                options.append({
                    "entry_id": entry_id,
                    "source_payslip_id": slip.get("id"),
                    "source_batch_id": slip.get("batch_id"),
                    "rider_id": rider_id,
                    "rider_name": slip.get("rider_name"),
                    "label": h.get("label"),
                    "type": h.get("type"),
                    "reduced_amount": reduced_amount,
                    "adjusted_at": h.get("adjusted_at"),
                    "reason": h.get("reason") or "",
                })

        options.sort(key=lambda x: str(x.get("adjusted_at") or ""), reverse=True)

        return {
            "rider_id": rider_id,
            "options_count": len(options),
            "options": options,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch carry-forward options: {str(e)}")


@app.post("/payroll/payslip/{payslip_id}/carry-forward/apply")
def apply_carry_forward_selections(
    payslip_id: str,
    data: CarryForwardApplyRequest,
    user=Depends(require_role("ACCOUNTANT")),
):
    """
    Apply carry-forward decisions to current draft payslip.
    decision:
      - all: apply full reduced amount
      - some: apply apply_amount
      - none: record decision only
    """
    try:
        payslip_res = supabase.table("payslips") \
            .select("*") \
            .eq("id", payslip_id) \
            .single() \
            .execute()
        payslip = payslip_res.data
        if not payslip:
            raise HTTPException(status_code=404, detail="Payslip not found")

        if str(payslip.get("status") or "").lower() == "finalized":
            raise HTTPException(status_code=400, detail="Finalized payslip cannot be edited")

        batch_id = payslip.get("batch_id")
        batch_res = supabase.table("payroll_batches") \
            .select("status") \
            .eq("id", batch_id) \
            .single() \
            .execute()
        batch = batch_res.data or {}
        if str(batch.get("status") or "").lower() not in ["draft", "error"]:
            raise HTTPException(status_code=400, detail="Only draft/error batches can be edited")

        items = [dict(i) for i in (payslip.get("items") or [])]
        issue_snapshot = payslip.get("issue_snapshot")
        issue_snapshot = issue_snapshot if isinstance(issue_snapshot, dict) else {}
        decisions = issue_snapshot.get("carry_forward_decisions")
        decisions = decisions if isinstance(decisions, list) else []

        applied_count = 0
        for sel in data.selections:
            decision = (sel.decision or "").strip().lower()
            if decision not in {"all", "some", "none"}:
                raise HTTPException(status_code=400, detail=f"Invalid decision '{sel.decision}'")

            apply_amount = 0.0
            if decision == "all":
                # Full amount is provided by caller in apply_amount for explicitness.
                apply_amount = float(sel.apply_amount or 0)
            elif decision == "some":
                apply_amount = float(sel.apply_amount or 0)
            else:
                apply_amount = 0.0

            if apply_amount < 0:
                raise HTTPException(status_code=400, detail="apply_amount cannot be negative")

            if apply_amount > 0:
                items.append({
                    "label": "Carry Forward Adjustment",
                    "amount": -abs(apply_amount),
                    "type": "deduction",
                    "subtype": "carry_forward",
                    "source": "carry_forward",
                    "entry_id": sel.entry_id,
                    "manual_override": True,
                })
                applied_count += 1

            decisions.append({
                "entry_id": sel.entry_id,
                "decision": decision,
                "apply_amount": apply_amount,
                "decided_by": user["id"],
                "decided_at": datetime.now().isoformat(),
                "target_payslip_id": payslip_id,
            })

        calc = recalc_payslip_totals_from_items(items)
        review_meta = build_payslip_review_meta({
            "status": payslip.get("status"),
            "rider_id": payslip.get("rider_id"),
            "net_salary": calc["net_salary"],
        })

        issue_snapshot["carry_forward_decisions"] = decisions[-2000:]

        payload = {
            "items": calc["items"],
            "net_salary": calc["net_salary"],
            "total_fines": calc["total_fines"],
            "total_expenses": calc["total_expenses"],
            "other_deductions": calc["other_deductions"],
            "review_required": review_meta["review_required"],
            "issue_codes": review_meta["issue_codes"],
            "issue_snapshot": issue_snapshot,
            "adjusted_by": user["id"],
            "adjusted_at": datetime.now().isoformat(),
        }

        upd = supabase.table("payslips") \
            .update(payload) \
            .eq("id", payslip_id) \
            .execute()

        return {
            "message": "Carry-forward decisions applied",
            "applied_count": applied_count,
            "payslip": upd.data[0] if upd.data else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to apply carry-forward: {str(e)}")


# Duplicate reports block removed. Consolidated in line 1636.


# ──────────────────────────────────────────────
#   RIDER ALIASES  (versioned platform IDs)
# ──────────────────────────────────────────────

class RiderAliasCreate(BaseModel):
    rider_id: str
    platform: str          # 'talabat' or 'keeta'
    platform_rider_id: str
    valid_from: str | None = None  # ISO date, defaults to today in DB

class RiderAliasUpdate(BaseModel):
    platform_rider_id: str | None = None
    valid_from: str | None = None
    valid_to: str | None = None


@app.get("/riders/{rider_id}/aliases")
def list_rider_aliases(
    rider_id: str,
    user=Depends(get_current_user),
):
    """Return all aliases for a rider, newest first."""
    try:
        res = supabase.table("rider_aliases") \
            .select("*") \
            .eq("rider_id", rider_id) \
            .order("valid_from", desc=True) \
            .execute()
        return {"aliases": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch aliases: {e}")


@app.post("/riders/{rider_id}/aliases")
def create_rider_alias(
    rider_id: str,
    data: RiderAliasCreate,
    user=Depends(require_role("ACCOUNTANT")),
):
    """
    Create a new alias.  Automatically deactivates (sets valid_to = today)
    any existing **active** alias on the same platform for this rider.
    """
    try:
        today = datetime.now().strftime("%Y-%m-%d")

        # Deactivate current active alias on the same platform
        supabase.table("rider_aliases") \
            .update({"valid_to": today}) \
            .eq("rider_id", rider_id) \
            .eq("platform", data.platform) \
            .is_("valid_to", "null") \
            .execute()

        row = {
            "rider_id": rider_id,
            "platform": data.platform,
            "platform_rider_id": data.platform_rider_id,
        }
        if data.valid_from:
            row["valid_from"] = data.valid_from

        res = supabase.table("rider_aliases").insert(row).execute()

        # Also update the convenience column on the riders table
        col = "talabat_id" if data.platform == "talabat" else "keeta_id"
        supabase.table("riders") \
            .update({col: data.platform_rider_id}) \
            .eq("id", rider_id) \
            .execute()

        return {"message": "Alias created", "alias": res.data[0] if res.data else None}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to create alias: {e}")


@app.patch("/riders/{rider_id}/aliases/{alias_id}")
def update_rider_alias(
    rider_id: str,
    alias_id: str,
    data: RiderAliasUpdate,
    user=Depends(require_role("ACCOUNTANT")),
):
    """Update an alias (e.g. set valid_to to deactivate)."""
    try:
        updates = {}
        if data.platform_rider_id is not None:
            updates["platform_rider_id"] = data.platform_rider_id
        if data.valid_from is not None:
            updates["valid_from"] = data.valid_from
        if data.valid_to is not None:
            updates["valid_to"] = data.valid_to

        if not updates:
            raise HTTPException(status_code=400, detail="Nothing to update")

        res = supabase.table("rider_aliases") \
            .update(updates) \
            .eq("id", alias_id) \
            .eq("rider_id", rider_id) \
            .execute()

        if not res.data:
            raise HTTPException(status_code=404, detail="Alias not found")

        return {"message": "Alias updated", "alias": res.data[0]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to update alias: {e}")


@app.delete("/riders/{rider_id}/aliases/{alias_id}")
def delete_rider_alias(
    rider_id: str,
    alias_id: str,
    user=Depends(require_role("ACCOUNTANT")),
):
    """Hard-delete an alias row."""
    try:
        res = supabase.table("rider_aliases") \
            .delete() \
            .eq("id", alias_id) \
            .eq("rider_id", rider_id) \
            .execute()

        if not res.data:
            raise HTTPException(status_code=404, detail="Alias not found")

        return {"message": "Alias deleted"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to delete alias: {e}")

# ==========================================
# Action Engine Endpoints (Step 6)
# ==========================================

@app.post("/actions/dismiss")
def dismiss_action(
    data: ActionDismissalRequest,
    user=Depends(get_current_user)
):
    try:
        # Try action_dismissals table first, fall back to action_log
        try:
            supabase.table("action_dismissals").insert({
                "action_id": data.action_id,
                "user_id": user["id"],
                "reason": data.reason
            }).execute()
        except Exception:
            # If action_dismissals doesn't exist, use audit_log table
            supabase.table("audit_log").insert({
                "action_type": "dismiss",
                "reference_table": "action_dismissals",
                "resolution_reason": f"{data.action_id}|{data.reason}",
                "resolved_by_user_id": user["id"]
            }).execute()
        return {"message": "Action permanently dismissed"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to dismiss action: {e}")

@app.get("/actions/dismissals")
def get_action_dismissals(
    user=Depends(get_current_user)
):
    try:
        try:
            res = supabase.table("action_dismissals") \
                .select("action_id") \
                .execute()
            dismissed_ids = [row["action_id"] for row in (res.data or [])]
        except Exception:
            # If action_dismissals doesn't exist, read from audit_log
            res = supabase.table("audit_log") \
                .select("resolution_reason") \
                .eq("action_type", "dismiss") \
                .eq("reference_table", "action_dismissals") \
                .execute()
            dismissed_ids = []
            for row in (res.data or []):
                reason = row.get("resolution_reason", "")
                if "|" in reason:
                    dismissed_ids.append(reason.split("|")[0])
        return {"dismissed_action_ids": dismissed_ids}
    except Exception as e:
        # If even action_log fails, return empty list gracefully
        print(f"Warning: Could not fetch dismissals: {e}")
        return {"dismissed_action_ids": []}


# --- Action Items from DB (new endpoints) ---

def _normalize_action_item_navigation(item: dict) -> dict:
    normalized = dict(item)
    action_type = (normalized.get("type") or "").strip().lower()
    route = (normalized.get("route") or "").strip()
    action_id = (normalized.get("id") or "").strip()
    argument_id = normalized.get("argument_id")
    reference_id = normalized.get("reference_id")

    # Backfill argument_id from reference_id for legacy rows.
    if not argument_id and reference_id:
        normalized["argument_id"] = reference_id

    subtitle = (normalized.get("subtitle") or "").strip()
    if not subtitle:
        default_reason_by_type = {
            "alias_mismatch": "Rider alias mismatch detected. Resolve rider mapping before finalization.",
            "journal_pending_approval": "Journal is pending accountant approval.",
            "rider_pending_approval": "Rider profile requires accountant review before use.",
            "insufficient_funds": "Insufficient drawer funds for the requested posting.",
            "bike_overlap": "Bike assignment dates overlap. Resolve assignment conflict first.",
            "duplicate_payslip": "Duplicate payslip detected for rider/month/platform.",
            "fine_unmatched": "Fine is unmatched and must be assigned before payroll operations.",
        }
        normalized["subtitle"] = default_reason_by_type.get(
            action_type,
            "Action requires review before continuing.",
        )

    if action_type == "alias_mismatch":
        normalized["route"] = f"/alias-resolution/{action_id}" if action_id else "/actions"
        return normalized

    if action_type == "journal_pending_approval":
        normalized["route"] = "/journals"
        return normalized

    if action_type == "rider_pending_approval":
        # Action card already builds required extras when route contains rider-approval.
        normalized["route"] = "/accountant-dashboard/rider-approval"
        return normalized

    if action_type == "insufficient_funds":
        normalized["route"] = "/drawers"
        return normalized

    if action_type == "bike_overlap":
        normalized["route"] = "/assets"
        return normalized

    if action_type == "duplicate_payslip":
        normalized["route"] = "/payroll/draft"
        return normalized

    if action_type == "fine_unmatched":
        normalized["route"] = "/fines"
        return normalized

    if not route:
        normalized["route"] = "/actions"

    return normalized

@app.get("/action-items")
def list_action_items(
    user=Depends(get_current_user)
):
    """Fetch all unresolved action items from the DB action_items table."""
    try:
        res = supabase.table("action_items") \
            .select("*") \
            .is_("resolved_at", "null") \
            .order("created_at", desc=True) \
            .execute()

        items = res.data or []

        # Normalize routes/arguments so UI resolve buttons always deep-link correctly.
        items = [_normalize_action_item_navigation(i) for i in items]

        # Enrich with linked journal data if reference_id exists
        for item in items:
            if item.get("reference_id") and item.get("related_entity") == "journal":
                try:
                    journal_res = supabase.table("journals") \
                        .select("*, journal_lines(*)") \
                        .eq("id", item["reference_id"]) \
                        .single() \
                        .execute()
                    if journal_res.data:
                        item["linked_journal"] = journal_res.data
                        # Also fetch linked expense
                        exp_res = supabase.table("expenses") \
                            .select("*") \
                            .eq("journal_id", item["reference_id"]) \
                            .execute()
                        if exp_res.data:
                            item["linked_expense"] = exp_res.data[0]
                except Exception:
                    pass

        return {"action_items": items}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch action items: {e}")


@app.post("/action-items/{action_id}/resolve")
def resolve_action_item(
    action_id: str,
    user=Depends(get_current_user)
):
    """Mark an action_item as resolved."""
    try:
        res = supabase.table("action_items") \
            .update({
                "resolved_at": datetime.now().isoformat(),
                "resolved_by": user["id"],
                "resolution_notes": "Manually resolved",
            }) \
            .eq("id", action_id) \
            .execute()

        # Write audit_log
        write_audit_log(
            table_name="action_items",
            record_id=action_id,
            action="UPDATE",
            new_data={"resolved_at": datetime.now().isoformat()},
            user_id=user["id"],
        )

        return {
            "message": "Action item resolved",
            "action_item": res.data[0] if res.data else None,
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to resolve action item: {e}")
# --- Robust Date Parser ---
def robust_date_parser(val):
    if pd.isna(val) or str(val).strip() == "":
        return None
    if isinstance(val, datetime):
        return val
        
    # Handle Excel serial numbers (number of days since Dec 30, 1899)
    if isinstance(val, (int, float)):
        try:
            return pd.to_datetime(val, unit='D', origin='1899-12-30')
        except:
            return None
            
    s = str(val).strip()

    # Strict ISO first to avoid day/month flip (example: 2024-03-10 -> 2024-10-03)
    if re.match(r'^\d{4}-\d{2}-\d{2}$', s):
        try:
            return datetime.strptime(s, "%Y-%m-%d")
        except:
            pass
    if re.match(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$', s):
        try:
            return datetime.fromisoformat(s.replace(' ', 'T'))
        except:
            pass
    
    # Try common formats first
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d", "%d-%m-%Y", "%d/%m/%Y", "%m/%d/%Y"):
        try:
            return datetime.strptime(s, fmt)
        except:
            continue
            
    # Fallback to dateutil for non-ISO ambiguous formats
    try:
        return parse_date(s, dayfirst=True)
    except:
        return None


# --- Helper Functions for Dynamic Upload ---
def find_rider_by_name(name: str):
    """Attempt to resolve a rider UUID by their full name (case-insensitive)."""
    if not name or name == "nan":
        return None
    try:
        res = supabase.table("riders").select("id").ilike("name", f"%{name.strip()}%").execute()
        if res.data:
            return res.data[0]["id"]
    except Exception as e:
        print(f"Error resolving rider by name '{name}': {e}")
    return None

def find_chassis_by_plate(plate: str):
    """Find the chassis_number associated with a plate (cleaned)."""
    if not plate or plate == "nan":
        return None
    try:
        clean_plate = plate.replace("-", "").replace(" ", "").upper()
        res = supabase.table("bikes").select("chassis_number").eq("bike_id", plate).execute()
        if not res.data:
             # Try without dash too
             res = supabase.table("bikes").select("chassis_number").eq("bike_id", clean_plate).execute()
        
        if res.data:
            return res.data[0]["chassis_number"]
    except Exception as e:
        print(f"Error resolving chassis for plate '{plate}': {e}")
    return None
@app.post("/upload-dynamic-excel")
async def upload_dynamic_excel(
    file: UploadFile = File(...),
    user = Depends(require_role(["PRO", "ACCOUNTANT"]))
):
    """
    Centralized endpoint for Rider Master, Bike Master, and Assignment History.
    1. Rider Master: Upserts riders by Emirates ID or Platform ID.
    2. Bike Master: Upserts bikes by Chassis Number.
    3. Bike History: Creates assignments and CLOSES old ones for that chassis.
    """
    try:
        contents = await file.read()
        df = pd.read_excel(BytesIO(contents))
        
        # Lowercase headers for robustness
        df.columns = [str(c).strip().lower() for c in df.columns]
        
        summary = {"success": 0, "failed": 0, "logs": []}
        
        for idx, row in df.iterrows():
            try:
                # --- A. DATA EXTRACTION ---
                chassis = str(row.get('chassis number', row.get('chassis', ''))).strip()
                plate = str(row.get('plate no', row.get('plate', row.get('bike id', '')))).strip()
                rider_name = str(row.get('rider name', row.get('rider', row.get('full name', row.get('name', ''))))).strip()
                eid = str(row.get('emirates id', row.get('emirates id number', ''))).strip()
                rider_code = str(row.get('rider id', row.get('code', ''))).strip()
                
                # --- B. RIDER PROCESSING ---
                rider_uuid = None
                if rider_name and rider_name != "nan":
                    # 1. Upsert Rider
                    rider_data = {
                        "name": rider_name,
                        "status": "active"
                    }
                    if eid and eid != "nan":
                        rider_data["emirates_id_number"] = eid
                    if rider_code and rider_code != "nan":
                        rider_data["rider_code"] = rider_code
                        
                    # Find by EID, Code, or Name
                    query = supabase.table("riders").select("id")
                    if eid and eid != "nan":
                        query = query.eq("emirates_id_number", eid)
                    elif rider_code and rider_code != "nan":
                        query = query.eq("rider_code", rider_code)
                    else:
                        query = query.ilike("name", f"%{rider_name}%")
                        
                    res = query.execute()
                    if res.data:
                        rider_uuid = res.data[0]["id"]
                        supabase.table("riders").update(rider_data).eq("id", rider_uuid).execute()
                    else:
                        insert_res = supabase.table("riders").insert(rider_data).execute()
                        if insert_res.data:
                            rider_uuid = insert_res.data[0]["id"]

                # --- C. BIKE & ASSIGNMENT PROCESSING ---
                # Resolve Chassis fallback if missing but Plate exists
                if (not chassis or chassis == "nan") and (plate and plate != "nan"):
                    chassis = find_chassis_by_plate(plate)

                if chassis and chassis != "nan":
                    # 1. Upsert Bike
                    bike_data = {
                        "chassis_number": chassis,
                        "bike_id": plate if plate != "nan" else f"PENDING-{chassis[:6]}",
                        "status": "active"
                    }
                    supabase.table("bikes").upsert(bike_data, on_conflict="chassis_number").execute()
                    
                    # 2. Assignment logic
                    if rider_uuid:
                        assigned_at_raw = row.get('assigned date', row.get('assigned at', row.get('date', None)))
                        assigned_dt = robust_date_parser(assigned_at_raw) or datetime.now()
                        
                        # Close any active assignment for THIS chassis if it exists elsewhere
                        prev_iso = (assigned_dt - timedelta(seconds=1)).isoformat()
                        supabase.table("bike_assignment") \
                            .update({"returned_at": prev_iso}) \
                            .eq("chassis_number", chassis) \
                            .is_("returned_at", "null") \
                            .execute()
                        
                        # Create New Assignment
                        supabase.table("bike_assignment").insert({
                            "rider_id": rider_uuid,
                            "chassis_number": chassis,
                            "assigned_at": assigned_dt.isoformat(),
                            "rider_name": rider_name
                        }).execute()
                        
                if rider_uuid or (chassis and chassis != "nan"):
                    summary["success"] += 1
                    
            except Exception as e:
                summary["failed"] += 1
                summary["logs"].append(f"Row {idx+2}: {str(e)}")
                
        return summary
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Upload processing failed: {str(e)}")


