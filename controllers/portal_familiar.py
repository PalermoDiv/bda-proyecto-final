from flask import Blueprint, render_template, request, redirect, url_for, session, flash, abort
from datetime import date, datetime as _dt
import models.paciente as Paciente
import models.alerta as Alerta
import models.receta as Receta
import models.visita as Visita
import models.portal as Portal
from auth import contacto_requerido
from utils import haversine_m
from models.iot import ultima_lectura_gps
from models.zona import por_paciente as zonas_por_paciente

bp = Blueprint("portal_familiar", __name__, url_prefix="/portal-familiar")


@bp.route("/login", methods=["GET", "POST"])
def portal_login():
    if session.get("contacto_id"):
        return redirect(url_for("portal_familiar.portal_index"))
    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        pin   = request.form.get("pin", "").strip()
        rows     = Portal.login(email)
        contacto = next((r for r in rows if r["pin_acceso"] == pin), None)
        if contacto:
            session["contacto_id"]     = contacto["id_contacto"]
            session["contacto_nombre"] = contacto["nombre"] + " " + contacto["apellido_p"]
            return redirect(url_for("portal_familiar.portal_index"))
        flash("Correo o PIN incorrectos.", "error")
    return render_template("portal_familiar/login.html")


@bp.route("/logout")
def portal_logout():
    session.pop("contacto_id", None)
    session.pop("contacto_nombre", None)
    return redirect(url_for("portal_familiar.portal_login"))


@bp.route("/")
@contacto_requerido
def portal_index():
    contacto_id = session["contacto_id"]
    pacientes = Paciente.por_contacto(contacto_id)
    return render_template("portal_familiar/index.html", pacientes=pacientes)


@bp.route("/paciente/<int:id>")
@contacto_requerido
def portal_paciente(id):
    contacto_id = session["contacto_id"]

    if not Paciente.verificar_contacto(contacto_id, id):
        abort(403)

    paciente = Paciente.obtener(id)
    if not paciente:
        abort(404)

    hoy  = date.today()
    dob  = paciente["fecha_nacimiento"]
    edad = hoy.year - dob.year - ((hoy.month, hoy.day) < (dob.month, dob.day))

    _cuids_raw = Paciente.cuidadores(id)
    cuidadores = [
        {"nombre": f"{r['nombre_cuidador']} {r['apellido_p']}", "telefono": r["telefono_cuid"]}
        for r in _cuids_raw
    ]

    _gps_raw   = ultima_lectura_gps(id, 1)
    ultima_gps = {**_gps_raw, "ts": _gps_raw["fecha_hora"]} if _gps_raw else None

    zonas_seguras = zonas_por_paciente(id)

    dentro_zona        = False
    nombre_zona_actual = None
    if ultima_gps and zonas_seguras:
        for z in zonas_seguras:
            if haversine_m(ultima_gps["latitud"],  ultima_gps["longitud"],
                           z["latitud_centro"],    z["longitud_centro"]) <= float(z["radio_metros"]):
                dentro_zona        = True
                nombre_zona_actual = z["nombre_zona"]
                break

    now_dt = _dt.now()

    def _t_rel(ts):
        if ts is None:
            return None
        mins = int((now_dt - ts).total_seconds() / 60)
        if mins < 1:
            return "hace un momento"
        if mins < 60:
            return f"hace {mins} minuto{'s' if mins != 1 else ''}"
        hrs = mins // 60
        if hrs < 24:
            return f"hace {hrs} hora{'s' if hrs != 1 else ''}"
        dias = hrs // 24
        return f"hace {dias} día{'s' if dias != 1 else ''}"

    tiempo_gps          = _t_rel(ultima_gps["ts"]) if ultima_gps else None
    _act_row            = Paciente.ultima_actividad(id)
    ultima_actividad_ts = _act_row["ultima_actividad"] if _act_row else None
    alerta_critica      = Alerta.critica_por_paciente(id)

    if alerta_critica:
        estado_banner = 'critica'
    elif ultima_actividad_ts is None or (now_dt - ultima_actividad_ts).total_seconds() > 7200:
        estado_banner = 'sin_datos'
    else:
        estado_banner = 'ok'

    tiempo_actividad      = _t_rel(ultima_actividad_ts)
    tiempo_alerta_critica = _t_rel(alerta_critica["fecha_hora"]) if alerta_critica else None

    medicamentos    = Receta.adherencia_por_paciente(id)
    _dosis_row      = Receta.dosis_nfc_hoy(id)
    dosis_hoy       = int(_dosis_row["dosis_hoy"]) if _dosis_row else 0
    bateria_historial = list(reversed(Portal.bateria_historial(id, 20)))

    _ronda_row   = Portal.ultima_ronda_paciente(id)
    ultima_ronda = _ronda_row["ultima_ronda"] if _ronda_row else None

    return render_template(
        "portal_familiar/paciente.html",
        paciente=paciente,
        edad=edad,
        cuidadores=cuidadores,
        ultima_gps=ultima_gps,
        zonas_seguras=zonas_seguras,
        dentro_zona=dentro_zona,
        alertas_activas=Alerta.activas_por_paciente(id),
        alertas_historial=Alerta.historial_por_paciente(id),
        medicamentos=medicamentos,
        dosis_hoy=int(dosis_hoy),
        medicamentos_total=len(medicamentos),
        visitas=Visita.portal(id),
        ultima_ronda=ultima_ronda,
        estado_banner=estado_banner,
        tiempo_actividad=tiempo_actividad,
        alerta_critica=alerta_critica,
        tiempo_alerta_critica=tiempo_alerta_critica,
        nombre_zona_actual=nombre_zona_actual,
        tiempo_gps=tiempo_gps,
        bateria_historial=bateria_historial,
    )
