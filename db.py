import os
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

load_dotenv()


def get_conn():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", 5432)),
        dbname=os.getenv("DB_NAME", "alzheimer"),
        user=os.getenv("DB_USER", "palermingoat"),
        password=os.getenv("DB_PASSWORD", "") or None,
    )


def query(sql, params=None):
    """Run SELECT and return list of RealDictRow."""
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params or ())
            return cur.fetchall()
    finally:
        conn.close()


def one(sql, params=None):
    """Run SELECT and return first row as RealDictRow, or None."""
    rows = query(sql, params)
    return rows[0] if rows else None


def scalar(sql, params=None):
    """Run SELECT and return first column of first row."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            row = cur.fetchone()
            return row[0] if row else None
    finally:
        conn.close()


def execute(sql, params=None):
    """Run INSERT / UPDATE / DELETE in its own transaction."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def execute_many(statements):
    """Run a list of (sql, params) tuples inside a single transaction."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            for sql, params in statements:
                cur.execute(sql, params or ())
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
