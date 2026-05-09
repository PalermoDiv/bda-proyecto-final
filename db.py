import os
import psycopg
from psycopg.rows import dict_row
from dotenv import load_dotenv

load_dotenv()


def get_conn():
    return psycopg.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", 5432)),
        dbname=os.getenv("DB_NAME", "alzheimer"),
        user=os.getenv("DB_USER", "alzadmin"),
        password=os.getenv("DB_PASSWORD") or None,
    )


def query(sql, params=None):
    """Run SELECT and return list of dicts."""
    conn = get_conn()
    try:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, params or ())
            return cur.fetchall()
    finally:
        conn.close()


def one(sql, params=None):
    """Run SELECT and return first row as dict, or None."""
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


def query_sp(sp_name, params=None):
    """Call a SELECT stored procedure that returns a REFCURSOR and fetch all rows."""
    conn = get_conn()
    try:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("BEGIN")
            cursor_name = "io_resultados"
            if params:
                placeholders = ", ".join(["%s"] * len(params))
                cur.execute(f"CALL {sp_name}({placeholders}, %s)", (*params, cursor_name))
            else:
                cur.execute(f"CALL {sp_name}(%s)", (cursor_name,))
            cur.execute(f"FETCH ALL FROM {cursor_name}")
            rows = cur.fetchall()
            cur.execute("COMMIT")
            return rows
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def one_sp(sp_name, params=None):
    """Like query_sp but returns only the first row."""
    rows = query_sp(sp_name, params)
    return rows[0] if rows else None


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
