from functools import wraps
from flask import session, redirect, url_for, request

_IOT_KEY = "alz-dev-2026"


def admin_requerido(f):
    @wraps(f)
    def decorado(*args, **kwargs):
        if not session.get("admin"):
            return redirect(url_for("auth.login"))
        return f(*args, **kwargs)
    return decorado


def medico_requerido(f):
    @wraps(f)
    def decorado(*args, **kwargs):
        if not session.get("medico"):
            return redirect(url_for("auth.login"))
        return f(*args, **kwargs)
    return decorado


def contacto_requerido(f):
    @wraps(f)
    def decorado(*args, **kwargs):
        if not session.get("contacto_id"):
            return redirect(url_for("portal_familiar.portal_login"))
        return f(*args, **kwargs)
    return decorado


def iot_auth():
    if session.get("admin") or session.get("medico"):
        return True
    return request.headers.get("X-AlzMonitor-Key", "") == _IOT_KEY
