import os
import secrets
import sqlite3
from datetime import datetime
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="HyperLink License & Subscription Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = os.getenv("DB_PATH", "hyperlink.db")
ADMIN_SECRET_KEY = os.getenv("ADMIN_SECRET_KEY", "HYPER_ADMIN_2026")


def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''
        CREATE TABLE IF NOT EXISTS subscriptions (
            subscription_key TEXT PRIMARY KEY,
            owner_name TEXT,
            max_licenses INTEGER,
            used_licenses INTEGER DEFAULT 0,
            is_active INTEGER DEFAULT 1,
            created_at TEXT
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS licenses (
            license_key TEXT PRIMARY KEY,
            subscription_key TEXT,
            phone_number TEXT,
            cookies TEXT,
            local_storage TEXT,
            created_at TEXT
        )
    ''')
    conn.commit()
    conn.close()


init_db()


class CreateSubscriptionReq(BaseModel):
    admin_key: str
    owner_name: str
    max_licenses: int = 1000


class CreateLicenseReq(BaseModel):
    cookies: str
    local_storage: str
    phone_number: str = "unknown"
    subscription_key: str


@app.post("/api/admin/subscriptions")
def create_subscription(req: CreateSubscriptionReq):
    if req.admin_key != ADMIN_SECRET_KEY:
        raise HTTPException(status_code=403, detail="کلید ادمین نامعتبر است")

    sub_key = "SUB-HYPER-" + secrets.token_hex(4).upper()
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M")

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute(
        "INSERT INTO subscriptions (subscription_key, owner_name, max_licenses, used_licenses, is_active, created_at) VALUES (?, ?, ?, 0, 1, ?)",
        (sub_key, req.owner_name, req.max_licenses, now),
    )
    conn.commit()
    conn.close()

    return {
        "success": True,
        "subscription_key": sub_key,
        "owner_name": req.owner_name,
        "max_licenses": req.max_licenses,
    }


@app.get("/api/admin/subscriptions")
def list_subscriptions(admin_key: str = Query(...)):
    if admin_key != ADMIN_SECRET_KEY:
        raise HTTPException(status_code=403, detail="کلید ادمین نامعتبر است")

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    rows = c.execute("SELECT * FROM subscriptions ORDER BY created_at DESC").fetchall()
    conn.close()

    return {
        "subscriptions": [
            {
                "subscription_key": r["subscription_key"],
                "owner_name": r["owner_name"],
                "max_licenses": r["max_licenses"],
                "used_licenses": r["used_licenses"],
                "remaining": max(0, r["max_licenses"] - r["used_licenses"]),
                "is_active": bool(r["is_active"]),
                "created_at": r["created_at"],
            }
            for r in rows
        ]
    }


@app.patch("/api/admin/subscriptions/{sub_key}/toggle")
def toggle_subscription(sub_key: str, admin_key: str = Query(...)):
    if admin_key != ADMIN_SECRET_KEY:
        raise HTTPException(status_code=403, detail="کلید ادمین نامعتبر است")

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute(
        "UPDATE subscriptions SET is_active = CASE WHEN is_active = 1 THEN 0 ELSE 1 END WHERE subscription_key = ?",
        (sub_key,),
    )
    conn.commit()
    conn.close()
    return {"success": True}


@app.delete("/api/admin/subscriptions/{sub_key}")
def delete_subscription(sub_key: str, admin_key: str = Query(...)):
    if admin_key != ADMIN_SECRET_KEY:
        raise HTTPException(status_code=403, detail="کلید ادمین نامعتبر است")

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("DELETE FROM subscriptions WHERE subscription_key = ?", (sub_key,))
    conn.commit()
    conn.close()
    return {"success": True}


@app.get("/api/subscription/status")
def get_subscription_status(sub_key: str = Query(...)):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    row = c.execute(
        "SELECT * FROM subscriptions WHERE subscription_key = ?", (sub_key,)
    ).fetchone()
    conn.close()

    if not row:
        raise HTTPException(status_code=404, detail="کد اشتراک یافت نشد")

    return {
        "subscription_key": row["subscription_key"],
        "owner_name": row["owner_name"],
        "max_licenses": row["max_licenses"],
        "used_licenses": row["used_licenses"],
        "remaining": max(0, row["max_licenses"] - row["used_licenses"]),
        "is_active": bool(row["is_active"]),
    }


@app.post("/api/tapsi/create-license")
def create_license(req: CreateLicenseReq):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    sub = c.execute(
        "SELECT * FROM subscriptions WHERE subscription_key = ?",
        (req.subscription_key,),
    ).fetchone()

    if not sub:
        conn.close()
        raise HTTPException(status_code=403, detail="کد اشتراک نامعتبر است.")

    if not sub["is_active"]:
        conn.close()
        raise HTTPException(status_code=403, detail="این اشتراک مسدود شده است.")

    if sub["used_licenses"] >= sub["max_licenses"]:
        conn.close()
        raise HTTPException(
            status_code=403,
            detail=f"ظرفیت اشتراک شما ({sub['max_licenses']} لایسنس) به پایان رسیده است.",
        )

    license_key = "HYP-" + secrets.token_hex(6).upper()
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M")

    c.execute(
        "INSERT INTO licenses (license_key, subscription_key, phone_number, cookies, local_storage, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        (
            license_key,
            req.subscription_key,
            req.phone_number,
            req.cookies,
            req.local_storage,
            now,
        ),
    )
    c.execute(
        "UPDATE subscriptions SET used_licenses = used_licenses + 1 WHERE subscription_key = ?",
        (req.subscription_key,),
    )
    conn.commit()
    conn.close()

    return {
        "success": True,
        "license_key": license_key,
        "remaining": sub["max_licenses"] - (sub["used_licenses"] + 1),
    }


@app.get("/api/licenses")
def get_licenses(sub_key: str = "", admin_key: str = ""):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    if admin_key == ADMIN_SECRET_KEY and admin_key != "":
        rows = c.execute(
            "SELECT license_key, subscription_key, phone_number, created_at FROM licenses ORDER BY created_at DESC"
        ).fetchall()
    elif sub_key:
        rows = c.execute(
            "SELECT license_key, subscription_key, phone_number, created_at FROM licenses WHERE subscription_key = ? ORDER BY created_at DESC",
            (sub_key,),
        ).fetchall()
    else:
        conn.close()
        raise HTTPException(status_code=403, detail="کد اشتراک یا کلید ادمین الزامی است")

    conn.close()
    return {"licenses": [dict(r) for r in rows]}


@app.delete("/api/licenses/{license_key}")
def delete_license(license_key: str, sub_key: str = "", admin_key: str = ""):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    if admin_key == ADMIN_SECRET_KEY and admin_key != "":
        c.execute("DELETE FROM licenses WHERE license_key = ?", (license_key,))
    elif sub_key:
        c.execute(
            "DELETE FROM licenses WHERE license_key = ? AND subscription_key = ?",
            (license_key, sub_key),
        )
    else:
        conn.close()
        raise HTTPException(status_code=403, detail="عدم دسترسی")

    conn.commit()
    conn.close()
    return {"success": True}
