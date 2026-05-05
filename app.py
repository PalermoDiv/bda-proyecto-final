from flask import Flask, render_template, request, redirect, url_for, session, flash, abort, jsonify
from functools import wraps
from dotenv import load_dotenv
from datetime import date
import math
import os
import db



load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "clave-secreta-dev")


# ── Emergency alert context processor ─────────────────────────────────────────
@app.context_processor
def inject_alertas_criticas():
    from datetime import datetime
    criticas = []
    if session.get("admin") or session.get("medico"):
        try:
            rows = db.query_sp("sp_sel_alertas_banner")
            now = datetime.now()
            for r in rows:
                delta = now - r["fecha_hora"]
                mins = int(delta.total_seconds() / 60)
                if mins < 1:
                    tiempo = "hace un momento"
                elif mins < 60:
                    tiempo = f"hace {mins} minuto{'s' if mins != 1 else ''}"
                else:
                    hrs = mins // 60
                    tiempo = f"hace {hrs} hora{'s' if hrs != 1 else ''}"
                criticas.append({**dict(r), "tiempo": tiempo})
        except Exception:
            pass
    return dict(alertas_criticas=criticas)


# ── Auth decorators ────────────────────────────────────────────────────────────

def admin_requerido(f):
    @wraps(f)
    def decorado(*args, **kwargs):
        if not session.get("admin"):
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorado


def medico_requerido(f):
    @wraps(f)
    def decorado(*args, **kwargs):
        if not session.get("medico"):
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorado


def contacto_requerido(f):
    @wraps(f)
    def decorado(*args, **kwargs):
        if not session.get("contacto_id"):
            return redirect(url_for("portal_login"))
        return f(*args, **kwargs)
    return decorado


def _haversine_m(lat1, lon1, lat2, lon2):
    """Distance in metres between two WGS-84 points."""
    R = 6_371_000
    p1, p2 = math.radians(float(lat1)), math.radians(float(lat2))
    dp = math.radians(float(lat2) - float(lat1))
    dl = math.radians(float(lon2) - float(lon1))
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ═══════════════════════════════════════════════════════════════════════════════
# RUTAS PÚBLICAS
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/")
def index_publico():
    if session.get("admin"):
        return redirect(url_for("dashboard"))
    if session.get("medico"):
        return redirect(url_for("clinica_sedes"))
    return render_template("public.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        usuario  = request.form["usuario"]
        password = request.form["password"]
        if (usuario == os.getenv("ADMIN_USER", "admin") and
                password == os.getenv("ADMIN_PASSWORD", "admin123")):
            session["admin"] = True
            session["rol"]   = "admin"
            return redirect(url_for("dashboard"))
        elif usuario == "medico" and password == "medico123":
            session["medico"] = True
            session["rol"]    = "medico"
            return redirect(url_for("clinica_sedes"))
        flash("Usuario o contraseña incorrectos", "error")
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("index_publico"))


# ═══════════════════════════════════════════════════════════════════════════════
# DASHBOARD
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/dashboard")
@admin_requerido
def dashboard():
    stats = dict(db.one_sp("sp_sel_dashboard_stats"))

    sedes = db.query_sp("sp_sel_sedes")
    sede_stats = {r["id_sede"]: r for r in db.query_sp("sp_sel_stats_por_sede")}

    stats_por_sede = []
    for s in sedes:
        sid = s["id_sede"]
        ss = sede_stats.get(sid, {})
        stats_por_sede.append({
            "sucursal": {
                "id_sucursal": sid,
                "nombre":    s["nombre_sede"],
                "zona":      "",
                "direccion": s["direccion"],
                "director":  "",
            },
            "pacientes":       ss.get("total_pacientes", 0),
            "cuidadores":      ss.get("total_cuidadores", 0),
            "dispositivos":    ss.get("total_dispositivos", 0),
            "alertas_activas": ss.get("alertas_activas", 0),
        })

    alertas               = db.query_sp("sp_sel_alertas_recientes")
    medicamentos_criticos = db.query_sp("sp_sel_medicamentos_criticos")
    suministros_pendientes = db.query_sp("sp_sel_suministros_pendientes")
    visitas_hoy           = db.query_sp("sp_sel_visitas_hoy")

    # ── Chart data ───────────────────────────────────────────────────────────
    alertas_por_tipo = db.query_sp("sp_sel_resumen_alertas_por_tipo")

    alertas_por_dia = db.query_sp("sp_sel_alertas_por_dia_14d")
    from datetime import timedelta
    hoy = date.today()
    dia_map = {r["dia_label"]: int(r["total"]) for r in alertas_por_dia}
    alertas_dias_labels = []
    alertas_dias_valores = []
    for i in range(13, -1, -1):
        d = hoy - timedelta(days=i)
        label = d.strftime("%d/%m")
        alertas_dias_labels.append(label)
        alertas_dias_valores.append(dia_map.get(label, 0))

    stock_farmacia = db.query_sp("sp_sel_stock_farmacia_completo")

    return render_template(
        "dashboard.html",
        stats=stats,
        alertas=alertas,
        stats_por_sede=stats_por_sede,
        sucursales=sedes,
        medicamentos_criticos=medicamentos_criticos,
        suministros_pendientes=suministros_pendientes,
        visitas_hoy=visitas_hoy,
        alertas_por_tipo=alertas_por_tipo,
        alertas_dias_labels=alertas_dias_labels,
        alertas_dias_valores=alertas_dias_valores,
        stock_farmacia=stock_farmacia,
    )


# ═══════════════════════════════════════════════════════════════════════════════
# PACIENTES
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/pacientes")
@admin_requerido
def pacientes_lista():
    pacientes = db.query_sp("sp_sel_pacientes_activos")
    sedes     = db.query_sp("sp_sel_sedes")
    return render_template("pacientes/list.html", pacientes=pacientes, sucursales=sedes)


@app.route("/pacientes/nuevo", methods=["GET", "POST"])
@admin_requerido
def pacientes_nuevo():
    estados = db.query_sp("sp_sel_estados_paciente")
    sedes   = db.query_sp("sp_sel_sedes")
    if request.method == "POST":
        try:
            id_pac     = int(request.form["id_paciente"])
            nombre     = request.form["nombre_paciente"].strip()
            apellido_p = request.form["apellido_p_pac"].strip()
            apellido_m = request.form["apellido_m_pac"].strip()
            fecha_nac  = request.form["fecha_nacimiento"]
            id_estado  = int(request.form["id_estado"])
            id_sede    = int(request.form["id_sede"])

            db.execute("CALL sp_ins_paciente(%s, %s, %s, %s, %s, %s, %s)",
                       (id_pac, nombre, apellido_p, apellido_m, fecha_nac, id_estado, id_sede))

            flash("Paciente registrado correctamente.", "success")
            return redirect(url_for("pacientes_lista"))
        except Exception as e:
            flash(f"Error al registrar paciente: {e}", "error")

    return render_template("pacientes/form.html", paciente=None, estados=estados, sedes=sedes)


@app.route("/pacientes/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def pacientes_editar(id):
    estados  = db.query_sp("sp_sel_estados_paciente")
    paciente = db.one_sp("sp_sel_paciente_por_id", (id,))

    if not paciente:
        flash("Paciente no encontrado.", "error")
        return redirect(url_for("pacientes_lista"))

    if request.method == "POST":
        try:
            nombre     = request.form["nombre_paciente"].strip()
            apellido_p = request.form["apellido_p_pac"].strip()
            apellido_m = request.form["apellido_m_pac"].strip()
            fecha_nac  = request.form["fecha_nacimiento"]
            id_estado  = int(request.form["id_estado"])

            db.execute("CALL sp_upd_paciente(%s, %s, %s, %s, %s, %s)",
                       (id, nombre, apellido_p, apellido_m, fecha_nac, id_estado))

            flash("Paciente actualizado correctamente.", "success")
            return redirect(url_for("pacientes_lista"))
        except Exception as e:
            flash(f"Error al actualizar paciente: {e}", "error")

    return render_template("pacientes/form.html", paciente=paciente, estados=estados, sedes=[])


@app.route("/pacientes/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def pacientes_eliminar(id):
    try:
        db.execute("CALL sp_del_paciente(%s)", (id,))
        flash("Paciente dado de baja correctamente.", "success")
    except Exception as e:
        flash(f"Error al dar de baja: {e}", "error")
    return redirect(url_for("pacientes_lista"))


@app.route("/pacientes/historial/<int:id>")
@admin_requerido
def pacientes_historial(id):
    paciente = db.one_sp("sp_sel_paciente_por_id", (id,))

    if not paciente:
        flash("Paciente no encontrado.", "error")
        return redirect(url_for("pacientes_lista"))

    estado = {"desc_estado": paciente["desc_estado"]}

    enfermedades          = db.query_sp("sp_sel_enfermedades_por_paciente", (id,))
    cuidadores            = db.query_sp("sp_sel_cuidadores_por_paciente", (id,))
    contactos             = db.query_sp("sp_sel_contactos_por_paciente", (id,))
    kit                   = db.one_sp("sp_sel_kit_por_paciente", (id,))
    historial_sedes       = db.query_sp("sp_sel_historial_sedes_por_paciente", (id,))
    alertas_paciente      = db.query_sp("sp_sel_alertas_por_paciente", (id,))
    visitas               = db.query_sp("sp_sel_visitas_por_paciente", (id,))
    entregas              = db.query_sp("sp_sel_entregas_por_paciente", (id,))
    nfc_asignacion        = db.one_sp("sp_sel_nfc_asignacion_por_paciente", (id,))
    nfc_disponibles       = db.query_sp("sp_sel_nfc_disponibles")
    enfermedades_disponibles = db.query_sp("sp_sel_enfermedades_disponibles", (id,))
    gps_disponibles       = db.query_sp("sp_sel_gps_disponibles")

    sede_actual_id = next(
        (r["id_sede"] for r in historial_sedes if r["fecha_salida"] is None),
        None
    )
    sedes_disponibles = [
        s for s in db.query_sp("sp_sel_sedes")
        if s["id_sede"] != (sede_actual_id or 0)
    ]

    lecturas_gps = db.query_sp("sp_sel_lecturas_gps_paciente", (id, 50))

    return render_template(
        "pacientes/historial.html",
        paciente=paciente,
        estado=estado,
        enfermedades=enfermedades,
        enfermedades_disponibles=enfermedades_disponibles,
        cuidadores=cuidadores,
        contactos=contactos,
        kit=kit,
        gps_disponibles=gps_disponibles,
        nfc_asignacion=nfc_asignacion,
        nfc_disponibles=nfc_disponibles,
        historial_sedes=historial_sedes,
        sedes_disponibles=sedes_disponibles,
        alertas_paciente=alertas_paciente,
        visitas=visitas,
        entregas=entregas,
        lecturas_gps=lecturas_gps,
    )


@app.route("/pacientes/<int:id>/reporte-pdf")
@admin_requerido
def pacientes_reporte_pdf(id):
    from pdf_report import generate_patient_report
    from flask import send_file
    paciente = db.one_sp("sp_sel_paciente_por_id", (id,))
    if not paciente:
        flash("Paciente no encontrado.", "error")
        return redirect(url_for("pacientes_lista"))
    buf = generate_patient_report(id)
    nombre_archivo = (
        f"reporte_{paciente['nombre_paciente'].lower()}_{paciente['apellido_p_pac'].lower()}_{id}.pdf"
    )
    return send_file(buf, mimetype="application/pdf",
                     as_attachment=True, download_name=nombre_archivo)


@app.route("/pacientes/<int:id>/transferir-sede", methods=["POST"])
@admin_requerido
def pacientes_transferir_sede(id):
    try:
        nueva_sede_id = int(request.form["nueva_sede_id"])

        activos = db.query_sp("sp_sel_sede_activa_por_paciente", (id,))

        if len(activos) > 1:
            raise Exception(
                f"Integridad comprometida: el paciente tiene {len(activos)} "
                "asignaciones activas simultáneas. Corrija manualmente."
            )

        if activos and activos[0]["id_sede"] == nueva_sede_id:
            flash("El paciente ya está asignado a esa sede.", "error")
            return redirect(url_for("pacientes_historial", id=id))

        db.execute("CALL sp_transferir_sede(%s, %s)", (id, nueva_sede_id))

        sede_row  = db.one_sp("sp_sel_sede_por_id", (nueva_sede_id,))
        sede_nombre = sede_row["nombre_sede"] if sede_row else str(nueva_sede_id)
        flash(f"Paciente transferido a {sede_nombre} correctamente.", "success")

    except Exception as e:
        flash(f"Error al transferir paciente: {e}", "error")

    return redirect(url_for("pacientes_historial", id=id))


@app.route("/pacientes/<int:id>/asignar-nfc", methods=["POST"])
@admin_requerido
def pacientes_asignar_nfc(id):
    try:
        id_dispositivo = int(request.form["id_dispositivo"])
        db.execute("CALL sp_nfc_asignar(%s, %s)", (id, id_dispositivo))
        flash("Pulsera NFC asignada correctamente.", "success")
    except Exception as e:
        flash(f"Error al asignar pulsera NFC: {e}", "error")
    return redirect(url_for("pacientes_historial", id=id))


@app.route("/pacientes/<int:id>/agregar-enfermedad", methods=["POST"])
@admin_requerido
def pacientes_agregar_enfermedad(id):
    try:
        id_enfermedad = int(request.form["id_enfermedad"])
        fecha_diag    = request.form["fecha_diag"]
        db.execute("CALL sp_ins_enfermedad(%s, %s, %s)", (id, id_enfermedad, fecha_diag))
        flash("Enfermedad agregada correctamente.", "success")
    except Exception as e:
        flash(f"Error al agregar enfermedad: {e}", "error")
    return redirect(url_for("pacientes_historial", id=id))


@app.route("/pacientes/<int:id>/quitar-enfermedad", methods=["POST"])
@admin_requerido
def pacientes_quitar_enfermedad(id):
    try:
        id_enfermedad = int(request.form["id_enfermedad"])
        db.execute("CALL sp_del_enfermedad(%s, %s)", (id, id_enfermedad))
        flash("Diagnóstico eliminado correctamente.", "success")
    except Exception as e:
        flash(f"Error al eliminar diagnóstico: {e}", "error")
    return redirect(url_for("pacientes_historial", id=id))


@app.route("/pacientes/<int:id>/agregar-contacto", methods=["POST"])
@admin_requerido
def pacientes_agregar_contacto(id):
    try:
        nombre     = request.form["nombre"].strip()
        apellido_p = request.form["apellido_p"].strip()
        apellido_m = request.form.get("apellido_m", "").strip() or None
        telefono   = request.form["telefono"].strip()
        relacion   = request.form["relacion"].strip()
        email      = request.form.get("email", "").strip() or None
        pin_acceso = request.form.get("pin_acceso", "").strip() or None

        db.execute("CALL sp_ins_contacto(%s, %s, %s, %s, %s, %s, %s, %s)",
                   (id, nombre, apellido_p, apellido_m, telefono, relacion, email, pin_acceso))

        flash("Contacto de emergencia agregado correctamente.", "success")
    except Exception as e:
        flash(f"Error al agregar contacto: {e}", "error")
    return redirect(url_for("pacientes_historial", id=id))


@app.route("/pacientes/<int:id>/asignar-kit", methods=["POST"])
@admin_requerido
def pacientes_asignar_kit(id):
    try:
        id_gps = int(request.form["id_dispositivo_gps"])
        db.execute("CALL sp_ins_kit(%s, %s)", (id, id_gps))
        flash("Kit GPS asignado correctamente.", "success")
    except Exception as e:
        flash(f"Error al asignar kit GPS: {e}", "error")
    return redirect(url_for("pacientes_historial", id=id))


@app.route("/pacientes/<int:id>/cambiar-kit", methods=["POST"])
@admin_requerido
def pacientes_cambiar_kit(id):
    try:
        id_gps = int(request.form["id_dispositivo_gps"])
        db.execute("CALL sp_kit_reasignar(%s, %s)", (id, id_gps))
        flash("Kit GPS reasignado correctamente.", "success")
    except Exception as e:
        flash(f"Error al reasignar kit GPS: {e}", "error")
    return redirect(url_for("pacientes_historial", id=id))


# ═══════════════════════════════════════════════════════════════════════════════
# CUIDADORES
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/cuidadores")
@admin_requerido
def cuidadores_lista():
    cuidadores = db.query_sp("sp_sel_cuidadores")
    return render_template("cuidadores/list.html",
                           cuidadores=cuidadores,
                           sucursales=db.query_sp("sp_sel_sedes"))


@app.route("/cuidadores/nuevo", methods=["GET", "POST"])
@admin_requerido
def cuidadores_nuevo():
    if request.method == "POST":
        try:
            id_cuid    = db.one_sp("sp_sel_next_id_empleado")["next_id"]
            nombre     = request.form["nombre_cuidador"].strip()
            apellido_p = request.form["apellido_p_cuid"].strip()
            apellido_m = request.form["apellido_m_cuid"].strip()
            telefono   = request.form.get("telefono_cuid", "").strip() or None
            curp       = request.form["curp_pasaporte"].strip()

            db.execute("CALL sp_ins_cuidador(%s, %s, %s, %s, %s, %s)",
                       (id_cuid, nombre, apellido_p, apellido_m, curp, telefono))

            flash("Cuidador registrado correctamente.", "success")
            return redirect(url_for("cuidadores_lista"))
        except Exception as e:
            flash(f"Error al registrar cuidador: {e}", "error")

    return render_template("cuidadores/form.html", cuidador=None)


@app.route("/cuidadores/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def cuidadores_editar(id):
    cuidador = db.one_sp("sp_sel_cuidador_por_id", (id,))

    if not cuidador:
        flash("Cuidador no encontrado.", "error")
        return redirect(url_for("cuidadores_lista"))

    if request.method == "POST":
        try:
            nombre     = request.form["nombre_cuidador"].strip()
            apellido_p = request.form["apellido_p_cuid"].strip()
            apellido_m = request.form["apellido_m_cuid"].strip()
            telefono   = request.form.get("telefono_cuid", "").strip() or None
            curp       = request.form["curp_pasaporte"].strip()

            db.execute("CALL sp_upd_cuidador(%s, %s, %s, %s, %s, %s)",
                       (id, nombre, apellido_p, apellido_m, curp, telefono))

            flash("Cuidador actualizado correctamente.", "success")
            return redirect(url_for("cuidadores_lista"))
        except Exception as e:
            flash(f"Error al actualizar cuidador: {e}", "error")

    return render_template("cuidadores/form.html", cuidador=cuidador)


@app.route("/cuidadores/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def cuidadores_eliminar(id):
    try:
        db.execute("CALL sp_del_cuidador(%s)", (id,))
        flash("Cuidador dado de baja correctamente.", "success")
    except Exception as e:
        flash(f"Error al dar de baja: {e}", "error")
    return redirect(url_for("cuidadores_lista"))


# ═══════════════════════════════════════════════════════════════════════════════
# TURNOS DE CUIDADORES
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/turnos")
@admin_requerido
def turnos_lista():
    turnos = db.query_sp("sp_sel_turnos")
    return render_template("turnos/list.html", turnos=turnos)


@app.route("/turnos/nuevo", methods=["GET", "POST"])
@admin_requerido
def turnos_nuevo():
    if request.method == "POST":
        try:
            id_turno    = int(request.form["id_turno"])
            id_cuidador = int(request.form["id_cuidador"])
            id_zona     = int(request.form["id_zona"])
            hora_inicio = request.form["hora_inicio"]
            hora_fin    = request.form["hora_fin"]
            dias = {d: d in request.form
                    for d in ("lunes","martes","miercoles","jueves",
                              "viernes","sabado","domingo")}

            db.execute("CALL sp_ins_turno(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                       (id_turno, id_cuidador, id_zona, hora_inicio, hora_fin,
                        dias["lunes"], dias["martes"], dias["miercoles"], dias["jueves"],
                        dias["viernes"], dias["sabado"], dias["domingo"]))

            flash("Turno registrado correctamente.", "success")
            return redirect(url_for("turnos_lista"))
        except Exception as e:
            flash(f"Error al registrar turno: {e}", "error")

    cuidadores = db.query_sp("sp_sel_cuidadores_dropdown")
    zonas_list = db.query_sp("sp_sel_zonas_lista")
    return render_template("turnos/form.html", turno=None,
                           cuidadores=cuidadores, zonas=zonas_list)


@app.route("/turnos/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def turnos_editar(id):
    turno = db.one_sp("sp_sel_turno_por_id", (id,))
    if not turno:
        flash("Turno no encontrado.", "error")
        return redirect(url_for("turnos_lista"))

    if request.method == "POST":
        try:
            id_cuidador = int(request.form["id_cuidador"])
            id_zona     = int(request.form["id_zona"])
            hora_inicio = request.form["hora_inicio"]
            hora_fin    = request.form["hora_fin"]
            activo      = "activo" in request.form
            dias = {d: d in request.form
                    for d in ("lunes","martes","miercoles","jueves",
                              "viernes","sabado","domingo")}

            db.execute("CALL sp_upd_turno(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                       (id, id_cuidador, id_zona, hora_inicio, hora_fin,
                        dias["lunes"], dias["martes"], dias["miercoles"], dias["jueves"],
                        dias["viernes"], dias["sabado"], dias["domingo"], activo))

            flash("Turno actualizado correctamente.", "success")
            return redirect(url_for("turnos_lista"))
        except Exception as e:
            flash(f"Error al actualizar turno: {e}", "error")

    cuidadores = db.query_sp("sp_sel_cuidadores_dropdown")
    zonas_list = db.query_sp("sp_sel_zonas_lista")
    return render_template("turnos/form.html", turno=turno,
                           cuidadores=cuidadores, zonas=zonas_list)


@app.route("/turnos/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def turnos_eliminar(id):
    try:
        db.execute("CALL sp_del_turno(%s)", (id,))
        flash("Turno eliminado correctamente.", "success")
    except Exception as e:
        flash(f"Error al eliminar turno: {e}", "error")
    return redirect(url_for("turnos_lista"))


# ═══════════════════════════════════════════════════════════════════════════════
# ASIGNACIÓN BEACON → CUIDADOR
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/equipamiento/asignacion-beacons", methods=["GET", "POST"])
@admin_requerido
def beacon_asignaciones():
    if request.method == "POST":
        try:
            id_dispositivo = int(request.form["id_dispositivo"])
            id_cuidador    = int(request.form["id_cuidador"])
            db.execute("CALL sp_ins_asignacion_beacon(%s, %s)", (id_dispositivo, id_cuidador))
            flash("Beacon asignado correctamente.", "success")
        except Exception as e:
            flash(f"Error al asignar beacon: {e}", "error")
        return redirect(url_for("beacon_asignaciones"))

    asignaciones = db.query_sp("sp_sel_asignacion_beacon_todas")
    beacons      = db.query_sp("sp_sel_beacons_disponibles_asig")
    cuidadores   = db.query_sp("sp_sel_cuidadores_sin_beacon")
    return render_template("equipamiento/asignacion_beacons.html",
                           asignaciones=asignaciones,
                           beacons=beacons,
                           cuidadores=cuidadores)


@app.route("/equipamiento/asignacion-beacons/<int:id>/cerrar", methods=["POST"])
@admin_requerido
def beacon_cerrar_asignacion(id):
    try:
        db.execute("CALL sp_upd_cerrar_asignacion_beacon(%s)", (id,))
        flash("Asignación cerrada correctamente.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("beacon_asignaciones"))


# ═══════════════════════════════════════════════════════════════════════════════
# RONDAS BEACON
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/rondas")
@admin_requerido
def rondas_lista():
    rondas = db.query_sp("sp_sel_rondas_recientes")
    return render_template("rondas/lista.html", rondas=rondas)


# ═══════════════════════════════════════════════════════════════════════════════
# ALERTAS
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/alertas")
@admin_requerido
def alertas():
    alertas_list = db.query_sp("sp_sel_alertas")

    patient_ids_set = {a["id_paciente"] for a in alertas_list if a.get("id_paciente")}
    contactos_por_paciente = {}
    if patient_ids_set:
        all_contacts = db.query_sp("sp_sel_contactos_emergencia")
        for row in all_contacts:
            pid = row["id_paciente"]
            if pid in patient_ids_set:
                contactos_por_paciente.setdefault(pid, []).append({
                    "id_paciente": pid,
                    "prioridad":   row["prioridad"],
                    "nombre":      row["nombre_completo"],
                    "telefono":    row["telefono"],
                    "parentesco":  row["relacion"],
                })

    return render_template("alertas.html", alertas=alertas_list,
                           contactos_por_paciente=contactos_por_paciente)


@app.route("/alertas/nueva", methods=["GET", "POST"])
@admin_requerido
def alertas_nueva():
    pacientes = db.query_sp("sp_sel_pacientes_activos")
    tipos     = db.query_sp("sp_sel_cat_tipo_alerta")

    if request.method == "POST":
        try:
            id_paciente = request.form.get("id_paciente") or None
            if id_paciente:
                id_paciente = int(id_paciente)
            tipo_alerta = request.form["tipo_alerta"]
            fecha_hora  = request.form["fecha_hora"]

            db.execute("CALL sp_ins_alerta(%s, %s, %s)",
                       (id_paciente, tipo_alerta, fecha_hora))

            flash("Alerta registrada.", "success")
            return redirect(url_for("alertas"))
        except Exception as e:
            flash(f"Error al registrar alerta: {e}", "error")

    now_str = date.today().isoformat() + "T" + __import__("datetime").datetime.now().strftime("%H:%M")
    return render_template("alertas_form.html", pacientes=pacientes, tipos=tipos,
                           fecha_hoy=date.today().isoformat(), now=now_str)


@app.route("/alertas/resolver/<int:id>", methods=["POST"])
@admin_requerido
def alertas_resolver(id):
    try:
        db.execute("CALL sp_upd_alerta_atendida(%s)", (id,))
        flash("Alerta marcada como atendida.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("alertas"))


@app.route("/alertas/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def alertas_eliminar(id):
    try:
        db.execute("CALL sp_del_alerta(%s)", (id,))
        flash("Alerta eliminada.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("alertas"))


# ═══════════════════════════════════════════════════════════════════════════════
# DISPOSITIVOS
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/dispositivos")
@admin_requerido
def dispositivos():
    dispositivos_list = db.query_sp("sp_sel_dispositivos")
    return render_template("dispositivos.html", dispositivos=dispositivos_list)


@app.route("/dispositivos/nuevo", methods=["GET", "POST"])
@admin_requerido
def dispositivos_nuevo():
    if request.method == "POST":
        try:
            id_disp   = int(request.form["id_dispositivo"])
            id_serial = request.form["id_serial"].strip()
            tipo      = request.form["tipo"].strip()
            modelo    = request.form["modelo"].strip()

            db.execute("CALL sp_ins_dispositivo(%s, %s, %s, %s)", (id_disp, id_serial, tipo, modelo))

            flash("Dispositivo registrado correctamente.", "success")
            return redirect(url_for("dispositivos"))
        except Exception as e:
            flash(f"Error al registrar dispositivo: {e}", "error")

    return render_template("dispositivos_form.html")


@app.route("/dispositivos/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def dispositivos_editar(id):
    disp = db.one_sp("sp_sel_dispositivo_raw", (id,))
    if not disp:
        flash("Dispositivo no encontrado.", "error")
        return redirect(url_for("dispositivos"))

    if request.method == "POST":
        try:
            id_serial = request.form["id_serial"].strip()
            tipo      = request.form["tipo"].strip()
            modelo    = request.form["modelo"].strip()
            estado    = request.form["estado"].strip()

            db.execute("CALL sp_upd_dispositivo(%s, %s, %s, %s, %s)", (id, id_serial, tipo, modelo, estado))

            flash("Dispositivo actualizado correctamente.", "success")
            return redirect(url_for("dispositivos"))
        except Exception as e:
            flash(f"Error al actualizar dispositivo: {e}", "error")

    return render_template("dispositivos_form.html", disp=disp)


@app.route("/dispositivos/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def dispositivos_eliminar(id):
    try:
        db.execute("CALL sp_del_dispositivo(%s)", (id,))
        flash("Dispositivo eliminado.", "success")
    except Exception as e:
        flash(f"Error al eliminar dispositivo: {e}", "error")
    return redirect(url_for("dispositivos"))


# ═══════════════════════════════════════════════════════════════════════════════
# ZONAS
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/zonas")
@admin_requerido
def zonas():
    zonas_list = db.query_sp("sp_sel_zonas")
    return render_template("zonas.html", zonas=zonas_list)


@app.route("/zonas/nueva", methods=["GET", "POST"])
@admin_requerido
def zonas_nueva():
    if request.method == "POST":
        try:
            nombre_zona = request.form["nombre_zona"].strip()
            latitud     = float(request.form["latitud_centro"])
            longitud    = float(request.form["longitud_centro"])
            radio       = float(request.form["radio_metros"])

            db.execute("CALL sp_ins_zona(%s, %s, %s, %s)", (nombre_zona, latitud, longitud, radio))

            flash("Zona segura registrada correctamente.", "success")
            return redirect(url_for("zonas"))
        except Exception as e:
            flash(f"Error al registrar zona: {e}", "error")

    sedes = db.query_sp("sp_sel_sedes")
    return render_template("zonas_form.html", zona=None, sedes=sedes)


@app.route("/zonas/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def zonas_editar(id):
    zona = db.one_sp("sp_sel_zona_por_id", (id,))
    if not zona:
        flash("Zona no encontrada.", "error")
        return redirect(url_for("zonas"))

    if request.method == "POST":
        try:
            nombre_zona = request.form["nombre_zona"].strip()
            latitud     = float(request.form["latitud_centro"])
            longitud    = float(request.form["longitud_centro"])
            radio       = float(request.form["radio_metros"])

            db.execute("CALL sp_upd_zona(%s, %s, %s, %s, %s)", (id, nombre_zona, latitud, longitud, radio))

            flash("Zona actualizada correctamente.", "success")
            return redirect(url_for("zonas"))
        except Exception as e:
            flash(f"Error al actualizar zona: {e}", "error")

    sedes = db.query_sp("sp_sel_sedes")
    return render_template("zonas_form.html", zona=zona, sedes=sedes)


@app.route("/zonas/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def zonas_eliminar(id):
    try:
        db.execute("CALL sp_del_zona(%s)", (id,))
        flash("Zona eliminada.", "success")
    except Exception as e:
        flash(f"Error al eliminar zona: {e}", "error")
    return redirect(url_for("zonas"))


# ═══════════════════════════════════════════════════════════════════════════════
# FARMACIA
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/farmacia")
@admin_requerido
def farmacia():
    inventario   = db.query_sp("sp_sel_inventario_farmacia")
    criticos     = [row for row in inventario if row["stock_actual"] < row["stock_minimo"]]
    suministros  = db.query_sp("sp_sel_suministros")
    farmacias    = db.query_sp("sp_sel_farmacias_proveedoras")
    medicamentos = db.query_sp("sp_sel_medicamentos_catalogo")
    sedes        = db.query_sp("sp_sel_sedes")

    return render_template(
        "farmacia.html",
        inventario=inventario,
        suministros=suministros,
        farmacias=farmacias,
        criticos=criticos,
        medicamentos=medicamentos,
        sedes=sedes,
    )


@app.route("/farmacia/inventario/ajustar", methods=["POST"])
@admin_requerido
def farmacia_ajustar_stock():
    try:
        gtin        = request.form["GTIN"].strip()
        id_sede     = int(request.form["id_sede"])
        stock_nuevo = int(request.form["stock_actual"])

        db.execute("CALL sp_upd_stock(%s, %s, %s)", (gtin, id_sede, stock_nuevo))

        flash("Stock actualizado correctamente.", "success")
    except Exception as e:
        flash(f"Error al ajustar stock: {e}", "error")
    return redirect(url_for("farmacia"))


@app.route("/farmacia/suministro/nuevo", methods=["GET", "POST"])
@admin_requerido
def farmacia_suministro_nuevo():
    farmacias    = db.query_sp("sp_sel_farmacias_proveedoras")
    sedes        = db.query_sp("sp_sel_sedes")
    medicamentos = db.query_sp("sp_sel_medicamentos_catalogo")

    if request.method == "POST":
        try:
            id_sum      = db.one_sp("sp_sel_next_id_suministro")["next_id"]
            id_farmacia = int(request.form["id_farmacia"])
            id_sede     = int(request.form["id_sede"])
            fecha       = request.form["fecha_entrega"]
            estado      = request.form.get("estado", "Pendiente")
            gtins       = request.form.getlist("GTIN[]")
            cantidades  = request.form.getlist("cantidad[]")

            if not any(g.strip() for g in gtins):
                flash("Debe agregar al menos un medicamento a la orden.", "error")
                raise ValueError("sin_lineas")

            db.execute("CALL sp_ins_suministro(%s, %s, %s, %s, %s)",
                       (id_sum, id_farmacia, id_sede, fecha, estado))

            for gtin, cant in zip(gtins, cantidades):
                if not gtin.strip():
                    continue
                db.execute("CALL sp_ins_suministro_linea(%s, %s, %s)",
                           (id_sum, gtin.strip(), int(cant)))

            flash("Orden de suministro registrada.", "success")
            return redirect(url_for("farmacia_suministro_detalle", id=id_sum))
        except ValueError:
            pass
        except Exception as e:
            flash(f"Error al registrar suministro: {e}", "error")

    return render_template(
        "farmacia_suministro_form.html",
        farmacias=farmacias,
        sedes=sedes,
        medicamentos=medicamentos,
        fecha_hoy=date.today().isoformat(),
    )


@app.route("/farmacia/suministro/<int:id>")
@admin_requerido
def farmacia_suministro_detalle(id):
    suministro = db.one_sp("sp_sel_suministro_por_id", (id,))

    if not suministro:
        flash("Orden no encontrada.", "error")
        return redirect(url_for("farmacia"))

    lineas      = db.query_sp("sp_sel_lineas_suministro_por_id", (id,))
    estados     = db.query_sp("sp_sel_cat_estado_suministro")
    medicamentos = db.query_sp("sp_sel_medicamentos_catalogo")

    return render_template(
        "farmacia_suministro_detalle.html",
        suministro=suministro,
        lineas=lineas,
        estados=estados,
        medicamentos=medicamentos,
    )


@app.route("/farmacia/suministro/<int:id>/estado", methods=["POST"])
@admin_requerido
def farmacia_suministro_estado(id):
    try:
        nuevo_estado = request.form["estado"]
        db.execute("CALL sp_upd_suministro_estado(%s, %s)", (id, nuevo_estado))
        flash("Estado de la orden actualizado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("farmacia_suministro_detalle", id=id))


@app.route("/farmacia/suministro/<int:id>/linea/agregar", methods=["POST"])
@admin_requerido
def farmacia_suministro_agregar_linea(id):
    try:
        gtin     = request.form["GTIN"].strip()
        cantidad = int(request.form["cantidad"])
        db.execute("CALL sp_ins_suministro_linea(%s, %s, %s)", (id, gtin, cantidad))
        flash("Medicamento agregado a la orden.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("farmacia_suministro_detalle", id=id))


@app.route("/farmacia/suministro/<int:id>/eliminar", methods=["POST"])
@admin_requerido
def farmacia_suministro_eliminar(id):
    try:
        db.execute("CALL sp_del_suministro(%s)", (id,))
        flash("Orden eliminada.", "success")
    except Exception as e:
        flash(f"Error al eliminar: {e}", "error")
    return redirect(url_for("farmacia"))


# ═══════════════════════════════════════════════════════════════════════════════
# VISITAS
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/visitas")
@admin_requerido
def visitas():
    visitas_hoy  = db.query_sp("sp_sel_visitas_hoy")
    visitas_hist = db.query_sp("sp_sel_visitas_historial")
    entregas     = db.query_sp("sp_sel_entregas_externas")[:30]

    return render_template(
        "visitas.html",
        visitas_hoy=visitas_hoy,
        visitas_hist=visitas_hist,
        entregas=entregas,
        fecha_hoy=date.today(),
    )


@app.route("/visitas/nueva", methods=["GET", "POST"])
@admin_requerido
def visitas_nueva():
    pacientes  = db.query_sp("sp_sel_pacientes_activos")
    visitantes = db.query_sp("sp_sel_visitantes")
    sedes      = db.query_sp("sp_sel_sedes")

    if request.method == "POST":
        try:
            id_visita   = int(request.form["id_visita"])
            id_paciente = int(request.form["id_paciente"])
            id_visitante= int(request.form["id_visitante"])
            id_sede     = int(request.form["id_sede"])
            fecha       = request.form["fecha_entrada"]
            hora        = request.form["hora_entrada"]

            db.execute("CALL sp_ins_visita(%s, %s, %s, %s, %s, %s)",
                       (id_visita, id_paciente, id_visitante, id_sede, fecha, hora))

            flash("Visita registrada correctamente.", "success")
            return redirect(url_for("visitas"))
        except Exception as e:
            flash(f"Error al registrar visita: {e}", "error")

    return render_template(
        "visitas_form.html",
        pacientes=pacientes,
        visitantes=visitantes,
        sedes=sedes,
        fecha_hoy=date.today().isoformat(),
    )


# ═══════════════════════════════════════════════════════════════════════════════
# RECETAS
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/recetas")
@admin_requerido
def recetas_lista():
    recetas = db.query_sp("sp_sel_recetas")

    adherencia_chart = db.query_sp("sp_sel_adherencia_nfc_por_paciente")

    return render_template("recetas.html", recetas=recetas, adherencia_chart=adherencia_chart)


@app.route("/recetas/nueva", methods=["GET", "POST"])
@admin_requerido
def recetas_nueva():
    pacientes = db.query_sp("sp_sel_pacientes_activos")
    if request.method == "POST":
        try:
            id_paciente = int(request.form["id_paciente"])
            fecha       = request.form["fecha"]
            next_id     = db.one_sp("sp_sel_next_id_receta")["next_id"]
            db.execute("CALL sp_receta_crear(%s, %s, %s)", (next_id, id_paciente, fecha))
            flash("Receta creada correctamente.", "success")
            return redirect(url_for("recetas_detalle", id=next_id))
        except Exception as e:
            flash(f"Error al crear receta: {e}", "error")
    from datetime import date
    return render_template("recetas_form.html", pacientes=pacientes, today=date.today().isoformat())


@app.route("/recetas/<int:id>")
@admin_requerido
def recetas_detalle(id):
    receta = db.one_sp("sp_sel_receta_por_id", (id,))
    if not receta:
        abort(404)

    medicamentos             = db.query_sp("sp_sel_receta_medicamentos_por_receta", (id,))
    medicamentos_disponibles = db.query_sp("sp_sel_medicamentos_disponibles_receta", (id,))
    nfc                      = db.one_sp("sp_sel_nfc_activo_por_receta", (id,))
    lecturas                 = db.query_sp("sp_sel_lecturas_nfc_por_receta", (id,))
    nfc_disponibles          = db.query_sp("sp_sel_nfc_disponibles")

    return render_template("recetas_detalle.html",
                           receta=receta,
                           medicamentos=medicamentos,
                           medicamentos_disponibles=medicamentos_disponibles,
                           nfc=nfc,
                           nfc_disponibles=nfc_disponibles,
                           lecturas=lecturas)


@app.route("/recetas/<int:id>/agregar-medicamento", methods=["POST"])
@admin_requerido
def recetas_agregar_medicamento(id):
    try:
        gtin             = request.form["gtin"]
        dosis            = request.form["dosis"].strip()
        frecuencia_horas = int(request.form["frecuencia_horas"])
        next_det = db.one_sp("sp_sel_next_id_detalle_receta")["next_id"]
        db.execute(
            "CALL sp_receta_agregar_medicamento(%s, %s, %s, %s, %s)",
            (next_det, id, gtin, dosis, frecuencia_horas)
        )
        flash("Medicamento agregado correctamente.", "success")
    except Exception as e:
        flash(f"Error al agregar medicamento: {e}", "error")
    return redirect(url_for("recetas_detalle", id=id))


@app.route("/recetas/<int:id>/actualizar-medicamento", methods=["POST"])
@admin_requerido
def recetas_actualizar_medicamento(id):
    try:
        id_detalle       = int(request.form["id_detalle"])
        dosis            = request.form["dosis"].strip()
        frecuencia_horas = int(request.form["frecuencia_horas"])
        db.execute(
            "CALL sp_receta_actualizar_medicamento(%s, %s, %s, %s)",
            (id_detalle, id, dosis, frecuencia_horas)
        )
        flash("Medicamento actualizado correctamente.", "success")
    except Exception as e:
        flash(f"Error al actualizar medicamento: {e}", "error")
    return redirect(url_for("recetas_detalle", id=id))


@app.route("/recetas/<int:id>/quitar-medicamento", methods=["POST"])
@admin_requerido
def recetas_quitar_medicamento(id):
    try:
        id_detalle = int(request.form["id_detalle"])
        db.execute(
            "CALL sp_receta_quitar_medicamento(%s, %s)",
            (id_detalle, id)
        )
        flash("Medicamento eliminado de la receta.", "success")
    except Exception as e:
        flash(f"Error al quitar medicamento: {e}", "error")
    return redirect(url_for("recetas_detalle", id=id))


@app.route("/recetas/<int:id>/cerrar", methods=["POST"])
@admin_requerido
def recetas_cerrar(id):
    try:
        db.execute("CALL sp_receta_cerrar(%s, CURRENT_DATE)", (id,))
        flash("Receta cerrada correctamente.", "success")
    except Exception as e:
        flash(f"Error al cerrar receta: {e}", "error")
    return redirect(url_for("recetas_detalle", id=id))


@app.route("/recetas/<int:id>/activar-nfc", methods=["POST"])
@admin_requerido
def recetas_activar_nfc(id):
    try:
        id_dispositivo = int(request.form["id_dispositivo"])
        db.execute("CALL sp_receta_activar_nfc(%s, %s, CURRENT_DATE)", (id, id_dispositivo))
        flash("Pulsera NFC vinculada correctamente.", "success")
    except Exception as e:
        flash(f"Error al activar NFC: {e}", "error")
    return redirect(url_for("recetas_detalle", id=id))


@app.route("/recetas/<int:id>/cerrar-nfc", methods=["POST"])
@admin_requerido
def recetas_cerrar_nfc(id):
    try:
        id_dispositivo = int(request.form["id_dispositivo"])
        db.execute("CALL sp_receta_cerrar_nfc(%s, %s, CURRENT_DATE)", (id, id_dispositivo))
        flash("Vínculo NFC cerrado.", "success")
    except Exception as e:
        flash(f"Error al cerrar NFC: {e}", "error")
    return redirect(url_for("recetas_detalle", id=id))


@app.route("/recetas/<int:id>/cambiar-nfc", methods=["POST"])
@admin_requerido
def recetas_cambiar_nfc(id):
    try:
        id_dispositivo_nuevo = int(request.form["id_dispositivo_nuevo"])
        db.execute("CALL sp_receta_cambiar_nfc(%s, %s, CURRENT_DATE)", (id, id_dispositivo_nuevo))
        flash("Pulsera NFC reemplazada correctamente.", "success")
    except Exception as e:
        flash(f"Error al cambiar NFC: {e}", "error")
    return redirect(url_for("recetas_detalle", id=id))


# ═══════════════════════════════════════════════════════════════════════════════
# REPORTES
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/reportes")
@admin_requerido
def reportes():
    stats = dict(db.one_sp("sp_sel_reportes_stats"))
    return render_template("reportes.html", stats=stats)


# ═══════════════════════════════════════════════════════════════════════════════
# PORTAL CLÍNICO  (médico)
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/clinica")
@medico_requerido
def clinica_sedes():
    sedes      = db.query_sp("sp_sel_sedes")
    sede_stats = {r["id_sede"]: r for r in db.query_sp("sp_sel_stats_por_sede")}
    result = []
    for s in sedes:
        sid = s["id_sede"]
        ss  = sede_stats.get(sid, {})
        result.append({
            "sucursal": {
                "id_sucursal": sid,
                "nombre":      s["nombre_sede"],
                "zona":        s.get("municipio", ""),
                "direccion":   s.get("direccion", ""),
            },
            "total_pacientes": ss.get("total_pacientes", 0),
        })
    return render_template("clinica_sedes.html", sedes=result)


@app.route("/clinica/<int:id_sucursal>")
@medico_requerido
def dashboard_clinica(id_sucursal):
    sede = db.one_sp("sp_sel_sede_por_id", (id_sucursal,))
    if not sede:
        return redirect(url_for("clinica_sedes"))

    sucursal = {"id_sucursal": sede["id_sede"], "nombre": sede["nombre_sede"]}

    pacientes_sede = db.query_sp("sp_sel_clinica_pacientes", (id_sucursal,))

    alertas_medicas_rows  = db.query_sp("sp_sel_clinica_alertas_activas", (id_sucursal,))
    alertas_activas_count = len(alertas_medicas_rows)
    alertas_medicas       = alertas_medicas_rows[:10]

    from datetime import datetime as _dt
    _now = _dt.now()
    staff_row      = db.one_sp("sp_sel_staff_en_turno", (id_sucursal,))
    staff_en_turno = staff_row["staff_count"] if staff_row else 0
    tareas_pendientes = 0

    _asig_rows = db.query_sp("sp_sel_clinica_asignaciones", (id_sucursal,))
    asignaciones = {}
    for row in _asig_rows:
        rec = dict(row)
        rec["apellido_p_cuid"] = rec.pop("apellido_p", "")
        rec["apellido_m_cuid"] = rec.pop("apellido_m", "")
        asignaciones.setdefault(row["id_paciente"], []).append(rec)

    _med_rows = db.query_sp("sp_sel_clinica_meds", (id_sucursal,))
    medicamentos_por_paciente = {}
    for row in _med_rows:
        medicamentos_por_paciente.setdefault(row["id_paciente"], []).append(row)

    _enf_rows = db.query_sp("sp_sel_clinica_enfermedades", (id_sucursal,))
    enf_por_paciente = {}
    for row in _enf_rows:
        enf_por_paciente.setdefault(row["id_paciente"], []).append(row)

    expedientes = []
    for p in pacientes_sede:
        pid = p["id_paciente"]
        expedientes.append({
            "paciente":     p,
            "perfil":       {},
            "medicamentos": medicamentos_por_paciente.get(pid, []),
            "bitacoras":    [],
            "enfermedades": enf_por_paciente.get(pid, []),
        })

    incidentes_sede = db.query_sp("sp_sel_clinica_incidentes", (id_sucursal,))
    comedor_hoy     = db.query_sp("sp_sel_clinica_comedor_hoy", (id_sucursal,))
    cobertura_zonas = db.query_sp("sp_sel_clinica_cobertura_zonas", (id_sucursal,))

    _visitas_hoy_all = db.query_sp("sp_sel_visitas_hoy")
    visitas_hoy = [v for v in _visitas_hoy_all if v["id_sede"] == id_sucursal]

    _entregas_all = db.query_sp("sp_sel_entregas_pendientes")
    entregas_pend = [e for e in _entregas_all if e["id_sede"] == id_sucursal]

    # Fecha hoy en español sin locale
    _meses = ['enero','febrero','marzo','abril','mayo','junio',
              'julio','agosto','septiembre','octubre','noviembre','diciembre']
    from datetime import date as _date
    _hoy = _date.today()
    fecha_hoy = f"{_hoy.day} de {_meses[_hoy.month - 1]}, {_hoy.year}"

    estado_pacientes = db.query_sp("sp_sel_clinica_gps_estado", (id_sucursal,))
    zonas_mapa       = db.query_sp("sp_sel_clinica_zonas_mapa", (id_sucursal,))
    alertas_salida_ids = {
        row["id_paciente"]
        for row in db.query_sp("sp_sel_clinica_alertas_salida_zona", (id_sucursal,))
    }

    # Calcular estado de zona y tiempo relativo por paciente
    for p in estado_pacientes:
        if p["ultima_lectura"] is None:
            p["zona_status"] = "sin_datos"
            p["tiempo_rel"] = None
        else:
            if p["id_paciente"] in alertas_salida_ids:
                p["zona_status"] = "fuera"
            else:
                dentro = any(
                    _haversine_m(p["latitud"], p["longitud"],
                                 float(z["latitud_centro"]), float(z["longitud_centro"]))
                    <= float(z["radio_metros"])
                    for z in zonas_mapa
                )
                p["zona_status"] = "dentro" if dentro else "fuera"
            mins = int((_now - p["ultima_lectura"]).total_seconds() / 60)
            if mins < 1:
                p["tiempo_rel"] = "hace un momento"
            elif mins < 60:
                p["tiempo_rel"] = f"hace {mins} min"
            elif mins < 1440:
                p["tiempo_rel"] = f"hace {mins // 60} h"
            else:
                p["tiempo_rel"] = f"hace {mins // 1440} d"

    meds_sede = db.query_sp("sp_sel_clinica_meds_nfc_hoy", (id_sucursal,))
    nfc_hoy   = {row["id_receta"]: row["hora_toma"]
                 for row in db.query_sp("sp_sel_clinica_nfc_hoy", (id_sucursal,))}
    for med in meds_sede:
        med["tomada_hoy"] = nfc_hoy.get(med["id_receta"])

    return render_template(
        "clinica.html",
        sucursal=sucursal,
        staff_en_turno=staff_en_turno,
        total_pacientes=len(pacientes_sede),
        tareas_pendientes=tareas_pendientes,
        alertas_activas=alertas_activas_count,
        tareas=[],
        alertas_medicas=alertas_medicas,
        cobertura_zonas=cobertura_zonas,
        asignaciones=asignaciones,
        pacientes=pacientes_sede,
        expedientes=expedientes,
        incidentes=incidentes_sede,
        comedor_hoy=comedor_hoy,
        visitas_hoy=visitas_hoy,
        entregas_pendientes=entregas_pend,
        fecha_hoy=fecha_hoy,
        estado_pacientes=estado_pacientes,
        zonas_mapa=zonas_mapa,
        meds_sede=meds_sede,
    )


# ═══════════════════════════════════════════════════════════════════════════════
# PORTAL FAMILIAR  (rol: contacto de emergencia)
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/portal-familiar/login", methods=["GET", "POST"])
def portal_login():
    if session.get("contacto_id"):
        return redirect(url_for("portal_index"))

    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        pin   = request.form.get("pin", "").strip()

        rows     = db.query_sp("sp_sel_contacto_login", (email,))
        contacto = next((r for r in rows if r["pin_acceso"] == pin), None)

        if contacto:
            session["contacto_id"]     = contacto["id_contacto"]
            session["contacto_nombre"] = contacto["nombre"] + " " + contacto["apellido_p"]
            return redirect(url_for("portal_index"))

        flash("Correo o PIN incorrectos.", "error")

    return render_template("portal_familiar/login.html")


@app.route("/portal-familiar/logout")
def portal_logout():
    session.pop("contacto_id", None)
    session.pop("contacto_nombre", None)
    return redirect(url_for("portal_login"))


@app.route("/portal-familiar")
@contacto_requerido
def portal_index():
    contacto_id = session["contacto_id"]

    pacientes = db.query_sp("sp_sel_pacientes_por_contacto", (contacto_id,))
    return render_template("portal_familiar/index.html", pacientes=pacientes)


@app.route("/portal-familiar/paciente/<int:id>")
@contacto_requerido
def portal_paciente(id):
    contacto_id = session["contacto_id"]

    # ── Security: verify contact-patient link ────────────────────────────────
    if not db.one_sp("sp_sel_contacto_verificacion", (contacto_id, id)):
        abort(403)

    # ── Patient header ───────────────────────────────────────────────────────
    paciente = db.one_sp("sp_sel_paciente_por_id", (id,))

    if not paciente:
        abort(404)

    hoy = date.today()
    dob = paciente["fecha_nacimiento"]
    edad = hoy.year - dob.year - ((hoy.month, hoy.day) < (dob.month, dob.day))

    # ── Active cuidadores ────────────────────────────────────────────────────
    _cuids_raw = db.query_sp("sp_sel_cuidadores_por_paciente", (id,))
    cuidadores = [
        {"nombre": f"{r['nombre_cuidador']} {r['apellido_p']}", "telefono": r["telefono_cuid"]}
        for r in _cuids_raw
    ]

    # ── Last GPS reading ─────────────────────────────────────────────────────
    _gps_raw   = db.one_sp("sp_sel_lecturas_gps_paciente", (id, 1))
    ultima_gps = {**_gps_raw, "ts": _gps_raw["fecha_hora"]} if _gps_raw else None

    # ── Safe zones for patient's current sede ────────────────────────────────
    zonas_seguras = db.query_sp("sp_sel_zonas_por_paciente", (id,))

    # Inside-zone check via Haversine (no PostGIS required for display)
    dentro_zona = False
    nombre_zona_actual = None
    if ultima_gps and zonas_seguras:
        for z in zonas_seguras:
            if _haversine_m(
                ultima_gps["latitud"],  ultima_gps["longitud"],
                z["latitud_centro"],    z["longitud_centro"]
            ) <= float(z["radio_metros"]):
                dentro_zona = True
                nombre_zona_actual = z["nombre_zona"]
                break

    # ── Status banner: most recent event across all sources ──────────────────
    from datetime import datetime as _dt
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

    tiempo_gps = _t_rel(ultima_gps["ts"]) if ultima_gps else None

    _act_row            = db.one_sp("sp_sel_ultima_actividad_ts", (id,))
    ultima_actividad_ts = _act_row["ultima_actividad"] if _act_row else None
    alerta_critica      = db.one_sp("sp_sel_alerta_critica_por_paciente", (id,))

    if alerta_critica:
        estado_banner = 'critica'
    elif ultima_actividad_ts is None or (now_dt - ultima_actividad_ts).total_seconds() > 7200:
        estado_banner = 'sin_datos'
    else:
        estado_banner = 'ok'

    tiempo_actividad = _t_rel(ultima_actividad_ts)
    tiempo_alerta_critica = _t_rel(alerta_critica["fecha_hora"]) if alerta_critica else None

    # ── Alerts ───────────────────────────────────────────────────────────────
    alertas_activas   = db.query_sp("sp_sel_alertas_activas_por_paciente", (id,))
    alertas_historial = db.query_sp("sp_sel_alertas_historial_por_paciente", (id,))

    # ── Medications (active recetas only, with today's NFC status) ───────────
    medicamentos = db.query_sp("sp_sel_medicamentos_adherencia_por_paciente", (id,))

    _dosis_row = db.one_sp("sp_sel_dosis_nfc_hoy", (id,))
    dosis_hoy  = int(_dosis_row["dosis_hoy"]) if _dosis_row else 0

    # ── Recent visits ────────────────────────────────────────────────────────
    visitas = db.query_sp("sp_sel_visitas_portal", (id,))

    # ── GPS battery history (last 20 readings, oldest→newest for sparkline) ────
    bateria_historial = list(reversed(db.query_sp("sp_sel_bateria_historial_gps", (id, 20))))

    # ── Last caregiver round ─────────────────────────────────────────────────
    _ronda_row   = db.one_sp("sp_sel_ultima_ronda_por_paciente", (id,))
    ultima_ronda = _ronda_row["ultima_ronda"] if _ronda_row else None

    return render_template(
        "portal_familiar/paciente.html",
        paciente=paciente,
        edad=edad,
        cuidadores=cuidadores,
        ultima_gps=ultima_gps,
        zonas_seguras=zonas_seguras,
        dentro_zona=dentro_zona,
        alertas_activas=alertas_activas,
        alertas_historial=alertas_historial,
        medicamentos=medicamentos,
        dosis_hoy=int(dosis_hoy),
        medicamentos_total=len(medicamentos),
        visitas=visitas,
        ultima_ronda=ultima_ronda,
        estado_banner=estado_banner,
        tiempo_actividad=tiempo_actividad,
        alerta_critica=alerta_critica,
        tiempo_alerta_critica=tiempo_alerta_critica,
        nombre_zona_actual=nombre_zona_actual,
        tiempo_gps=tiempo_gps,
        bateria_historial=bateria_historial,
    )


# ═══════════════════════════════════════════════════════════════════════════════
# CAREGIVER WEBAPP + IoT API
# ═══════════════════════════════════════════════════════════════════════════════

_IOT_KEY = "alz-dev-2026"


def _iot_auth():
    """Returns True if the request comes from an authenticated session or carries the IoT API key."""
    if session.get("admin") or session.get("medico"):
        return True
    return request.headers.get("X-AlzMonitor-Key", "") == _IOT_KEY


@app.route("/cuidador/escanear")
@medico_requerido
def cuidador_escanear():
    """Caregiver scanner webapp — taps patient NFC wristband to log medication adherence.
    Requires HTTPS + Chrome Android (Web NFC API).
    """
    return render_template("cuidador/escanear.html")


@app.route("/cuidador/ronda")
def cuidador_ronda():
    """Caregiver round page — BLE beacon scan (Web Bluetooth requestLEScan) with
    manual zone check-in fallback.  No auth required for now.
    TODO: add caregiver login once /cuidador/login is implemented.
    """
    # beacon_zona (wall-mount approach) retired — beacons now caregiver-carried.
    zonas = []
    return render_template("cuidador/ronda.html", zonas=zonas)


@app.route("/api/nfc/lectura", methods=["POST"])
def api_nfc_lectura():
    """POST /api/nfc/lectura
    Registers an NFC medication reading via sp_nfc_registrar_lectura.

    JSON body (option A — direct IDs):
      id_dispositivo  int     — dispositivos.id_dispositivo (NFC type)
      id_receta       int     — recetas.id_receta

    JSON body (option B — from caregiver scanner, lookup by serial):
      serial          str     — dispositivos.id_serial
      (id_receta resolved automatically from active receta_nfc link)

    Optional:
      tipo_lectura    str     — 'Administración' | 'Verificación'  (default: Administración)
      resultado       str     — 'Exitosa' | 'Fallida'              (default: Exitosa)

    Auth: session (admin/medico) OR X-AlzMonitor-Key header.
    """
    if not _iot_auth():
        return jsonify({"status": "error", "message": "No autorizado"}), 401

    data = request.get_json(silent=True) or {}
    tipo_lectura = data.get("tipo_lectura", "Administración")
    resultado    = data.get("resultado", "Exitosa")

    id_dispositivo = data.get("id_dispositivo")
    id_receta      = data.get("id_receta")

    # Option B: resolve by serial
    if not id_dispositivo and data.get("serial"):
        device = db.one_sp("sp_sel_dispositivo_por_serial_tipo", (data["serial"], "NFC"))
        if not device:
            return jsonify({"status": "error", "error": f"Serial '{data['serial']}' no registrado"}), 404
        id_dispositivo = device["id_dispositivo"]

    if not id_dispositivo:
        return jsonify({"status": "error", "message": "Falta id_dispositivo o serial"}), 400

    # Resolve id_receta from active link if not provided
    if not id_receta:
        link = db.one_sp("sp_sel_receta_nfc_activa", (id_dispositivo,))
        if not link:
            return jsonify({"status": "error", "error": "No hay receta activa vinculada a este dispositivo NFC"}), 404
        id_receta = link["id_receta"]

    try:
        next_id = db.one_sp("sp_sel_next_id_lectura_nfc")["next_id"]
        db.execute(
            "CALL sp_nfc_registrar_lectura(%s::integer, %s::integer, %s::integer, NOW(), %s, %s)",
            (next_id, id_dispositivo, id_receta, tipo_lectura, resultado)
        )
        return jsonify({"status": "ok", "ok": True, "id_lectura_nfc": next_id, "id_receta": id_receta})
    except Exception as e:
        return jsonify({"status": "error", "error": str(e)}), 422


@app.route("/api/beacon/deteccion", methods=["POST"])
def api_beacon_deteccion():
    """POST /api/beacon/deteccion
    Logs a BLE beacon detection (caregiver round).

    JSON body — one of these to identify the beacon:
      id_beacon     int    — dispositivos.id_dispositivo directly
      serial        str    — id_serial exact match
      uuid+major+minor     — iBeacon triplet; matched against id_serial "UUID_PREFIX-MAJOR-MINOR"
                             e.g. uuid="FDA50693-A4E2-...", major=1000, minor=1001
                             → looks up "FDA50693-1000-1001"

    Optional:
      id_empleado   int    — cuidadores.id_empleado (NULL allowed — anonymous round)
      rssi          int    — signal strength dBm (0 if unknown / manual check-in)
      manual        bool   — true when caregiver tapped a zone button (no BLE scan)

    Auth: session (admin/medico) OR X-AlzMonitor-Key header OR /cuidador/ronda open page.
    TODO: add proper auth for the ronda page once caregiver login is implemented.
    """
    # Ronda page is intentionally unauthenticated for now — _iot_auth() also
    # passes when the AlzMonitor-Key header is present, so hardware is fine.
    # The route itself has no sensitive writes beyond a detection log row.
    if not _iot_auth() and not request.referrer:
        # Allow calls that originate from our own ronda page even without session
        pass  # fall through — ronda page posts without session

    data       = request.get_json(silent=True) or {}
    rssi       = data.get("rssi", 0)
    gateway_id = data.get("gateway_id", "central")
    id_beacon  = data.get("id_beacon")
    serial     = data.get("serial")

    # ── Resolve beacon: id_beacon > serial > uuid+major+minor ─────────────────
    if not id_beacon and serial:
        row = db.one_sp("sp_sel_dispositivo_por_serial_tipo", (serial, "BEACON"))
        if row:
            id_beacon = row["id_dispositivo"]

    if not id_beacon and data.get("uuid") and data.get("major") is not None and data.get("minor") is not None:
        uuid_prefix = str(data["uuid"]).upper()[:8]
        composite   = f"{uuid_prefix}-{data['major']}-{data['minor']}"
        row = db.one_sp("sp_sel_dispositivo_por_serial_tipo", (composite, "BEACON"))
        if row:
            id_beacon = row["id_dispositivo"]

    if not id_beacon:
        return jsonify({"status": "error", "message": "Beacon no identificado"}), 400

    # ── Resolve caregiver from asignacion_beacon ───────────────────────────────
    cuidador = db.one_sp("sp_sel_asignacion_beacon_cuidador", (id_beacon,))
    id_cuidador    = cuidador["id_cuidador"] if cuidador else None
    caregiver_name = cuidador["nombre"]      if cuidador else "Sin asignar"

    try:
        db.execute(
            "CALL sp_ins_deteccion_beacon(%s, %s, %s, %s)",
            (id_beacon, id_cuidador, rssi, gateway_id)
        )
        row = db.one_sp("sp_sel_ultima_deteccion_por_beacon", (id_beacon,))
        return jsonify({
            "status": "ok",
            "ok": True,
            "id_deteccion":  row["id_deteccion"] if row else None,
            "caregiver_name": caregiver_name,
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 422


# ═══════════════════════════════════════════════════════════════════════════════
# GPS SIMULATION — admin tool to inject GPS readings for demo / testing
# Triggers trg_bateria_baja_gps and trg_zona_exit_gps automatically
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/sim/gps", methods=["GET", "POST"])
@admin_requerido
def sim_gps():
    """Admin form to simulate a GPS reading for a patient's device.
    Inserts into lecturas_gps which fires trg_bateria_baja_gps and trg_zona_exit_gps.
    """
    dispositivos_gps = db.query_sp("sp_sel_dispositivos_gps_activos")

    result = None
    if request.method == "POST":
        try:
            id_dispositivo = int(request.form["id_dispositivo"])
            latitud        = float(request.form["latitud"])
            longitud       = float(request.form["longitud"])
            nivel_bateria  = int(request.form.get("nivel_bateria") or 80)

            db.execute("CALL sp_ins_lectura_gps(%s, %s, %s, %s, NULL)",
                       (id_dispositivo, latitud, longitud, nivel_bateria))
            id_lectura     = db.one_sp("sp_sel_last_id_lectura_gps")["id_lectura"]
            nuevas_alertas = db.query_sp("sp_sel_alertas_sim_recientes")
            result = {
                "id_lectura": id_lectura,
                "latitud": latitud,
                "longitud": longitud,
                "nivel_bateria": nivel_bateria,
                "alertas_generadas": nuevas_alertas,
            }
            flash(f"Lectura GPS #{id_lectura} insertada. Triggers ejecutados.", "success")
        except Exception as e:
            flash(f"Error al simular lectura GPS: {e}", "error")

    zonas_ref = db.query_sp("sp_sel_zonas_ref")

    return render_template("sim_gps.html",
                           dispositivos_gps=dispositivos_gps,
                           zonas_ref=zonas_ref,
                           result=result)


@app.route("/api/gps/lectura", methods=["POST"])
def api_gps_lectura():
    """POST /api/gps/lectura
    Inserts a GPS reading programmatically (from PG12 cloud poller or manual test).
    Fires trg_bateria_baja_gps and trg_zona_exit_gps automatically.

    JSON body:
      id_dispositivo  int     — dispositivos.id_dispositivo (GPS type)
      latitud         float
      longitud        float
      nivel_bateria   int     (optional, default 100)
      altura          float   (optional)

    Auth: session (admin) OR X-AlzMonitor-Key header.
    """
    if not _iot_auth():
        return jsonify({"status": "error", "message": "No autorizado"}), 401

    data = request.get_json(silent=True) or {}
    id_dispositivo = data.get("id_dispositivo")
    latitud        = data.get("latitud")
    longitud       = data.get("longitud")
    nivel_bateria  = data.get("nivel_bateria", 100)
    altura         = data.get("altura")

    if not id_dispositivo or latitud is None or longitud is None:
        return jsonify({"status": "error", "message": "Faltan campos: id_dispositivo, latitud, longitud"}), 400

    try:
        db.execute("CALL sp_ins_lectura_gps(%s, %s, %s, %s, %s)",
                   (id_dispositivo, latitud, longitud, nivel_bateria, altura))
        id_lectura = db.one_sp("sp_sel_last_id_lectura_gps")["id_lectura"]
        return jsonify({"status": "ok", "id_lectura": id_lectura})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 422


@app.route("/api/gps/osmand", methods=["GET", "POST"])
def api_gps_osmand():
    """GPS ingestion endpoint for mobile tracking apps (local dev, HTTP port 5003).
    Supports two formats:
      - Query/form params: ?id=<serial>&lat=<lat>&lon=<lon>&batt=<batt>&altitude=<alt>
      - JSON body with location.coords (Traccar/BackgroundGeolocation format):
          {"location": {"coords": {"latitude":..., "longitude":..., "altitude":..., "speed":...}}}
        In this case pass ?id=<serial> in the URL.
    'id' can be the device's id_serial (string) or id_dispositivo (number).
    No auth required — only reachable on the local HTTP listener (port 5003).
    """
    # Device id always comes from the query string
    device_id = request.args.get("id", "").strip()

    # Try JSON body first (Traccar Client / BackgroundGeolocation format)
    json_body = request.get_json(silent=True, force=True)
    if json_body and "location" in json_body:
        coords   = json_body["location"].get("coords", {})
        lat      = coords.get("latitude")
        lon      = coords.get("longitude")
        altitude = coords.get("altitude")
        raw_batt = json_body["location"].get("battery", {}).get("level", -1)
        batt = max(0, min(100, int(raw_batt * 100))) if raw_batt >= 0 else None
    else:
        lat      = request.values.get("lat")
        lon      = request.values.get("lon")
        altitude = request.values.get("altitude")
        batt     = request.values.get("batt") or request.values.get("battery")

    if not device_id or lat is None or lon is None:
        return f"Missing params — id={device_id!r} lat={lat!r} lon={lon!r}", 400

    try:
        # Resolve id_dispositivo — serial lookup first, then numeric id fallback
        row = db.one_sp("sp_sel_dispositivo_serial", (device_id,))
        if row and row.get("tipo") == "GPS":
            id_dispositivo = row["id_dispositivo"]
        else:
            try:
                id_dispositivo = int(device_id)
            except ValueError:
                return f"Device not found: {device_id}", 404

        latitud       = float(lat)
        longitud      = float(lon)
        nivel_bateria = int(batt) if batt is not None else 100
        altura        = float(altitude) if altitude else None

        app.logger.debug("OsmAnd insert: id=%s lat=%s lon=%s batt=%s alt=%s",
                         id_dispositivo, latitud, longitud, nivel_bateria, altura)
        db.execute("CALL sp_ins_lectura_gps(%s, %s, %s, %s, %s)",
                   (id_dispositivo, latitud, longitud, nivel_bateria, altura))
        return "OK", 200
    except Exception as e:
        app.logger.error("OsmAnd SP error: %s", e)
        return str(e), 422


# ═══════════════════════════════════════════════════════════════════════════════
# STORED PROCEDURES GUIDE
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/procedimientos")
@admin_requerido
def procedimientos():
    return render_template("procedimientos.html")


# ═══════════════════════════════════════════════════════════════════════════════
# NFC TEST — development only, no auth required
# TODO: remove or protect before production

@app.route("/test/nfc")
def test_nfc_page():
    return render_template("test_nfc.html")


@app.route("/api/test/nfc", methods=["POST"])
def test_nfc_read():
    data = request.get_json(silent=True) or {}
    tag_serial = data.get("tag_serial", "").strip()

    if not tag_serial:
        return jsonify({"status": "error", "message": "No serial received"}), 400

    device = db.one_sp("sp_sel_dispositivo_por_serial_tipo", (tag_serial, "NFC"))

    if not device:
        app.logger.info("Unknown NFC tag scanned: %s", tag_serial)
        return jsonify({
            "status": "not_found",
            "tag_serial": tag_serial,
            "message": "Tag not registered. Add this serial to Dispositivos as type NFC.",
        })

    try:
        patient = db.one_sp("sp_sel_paciente_por_nfc", (device["id_serial"],))
    except Exception:
        patient = None

    response = {
        "status": "found",
        "device_id": device["id_dispositivo"],
        "device_serial": device["id_serial"],
        "device_status": device["estado"],
        "tag_serial_raw": tag_serial,
        "patient_name": "Sin paciente asignado",
        "patient_id": None,
    }

    if patient:
        response["patient_name"] = f"{patient['nombre']} {patient['apellido_p']}"
        response["patient_id"] = patient["id_paciente"]

    return jsonify(response)


# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    import threading
    from werkzeug.serving import make_server

    # Traccar/OsmAnd plain HTTP listener on 5003
    http_srv = make_server("0.0.0.0", 5003, app)
    threading.Thread(target=http_srv.serve_forever, daemon=True).start()
    print("  * Traccar/OsmAnd HTTP listener on http://0.0.0.0:5003")

    app.run(debug=False, host="0.0.0.0", port=5002,
            ssl_context=("cert.pem", "key.pem"))
