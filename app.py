from flask import Flask, render_template, request, redirect, url_for, session, flash, abort, jsonify
from functools import wraps
from dotenv import load_dotenv
from datetime import date
import math
import os
import db
import data  # clinica-specific in-memory structures not yet in DB

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
            rows = db.query("""
                SELECT a.id_alerta,
                       COALESCE(p.nombre || ' ' || p.apellido_p, 'Zona') AS nombre_paciente,
                       a.fecha_hora,
                       a.tipo_alerta
                FROM alertas a
                LEFT JOIN pacientes p ON a.id_paciente = p.id_paciente
                WHERE a.estatus = 'Activa'
                  AND a.tipo_alerta IN ('Salida de Zona', 'Botón SOS', 'Caída')
                ORDER BY a.fecha_hora DESC
            """)
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
    stats = {
        "pacientes":      db.scalar("SELECT COUNT(*) FROM pacientes WHERE id_estado != 3"),
        "cuidadores":     db.scalar("SELECT COUNT(*) FROM cuidadores"),
        "dispositivos":   db.scalar("SELECT COUNT(*) FROM dispositivos WHERE estado = 'Activo'"),
        "alertas_activas": db.scalar("SELECT COUNT(*) FROM alertas WHERE estatus = 'Activa'"),
    }

    sedes = db.query("""
        SELECT id_sede,
               nombre_sede,
               calle || ' ' || numero || ', ' || municipio AS direccion
        FROM sedes
        ORDER BY id_sede
    """)

    stats_por_sede = []
    for s in sedes:
        sid = s["id_sede"]
        stats_por_sede.append({
            "sucursal": {
                "id_sucursal": sid,
                "nombre":    s["nombre_sede"],
                "zona":      "",
                "direccion": s["direccion"],
                "director":  "",
            },
            "pacientes": db.scalar("""
                SELECT COUNT(*) FROM pacientes p
                JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                WHERE sp.id_sede = %s AND sp.fecha_salida IS NULL AND p.id_estado != 3
            """, (sid,)) or 0,
            "cuidadores": db.scalar("""
                SELECT COUNT(DISTINCT se.id_empleado)
                FROM sede_empleados se
                JOIN cuidadores c ON se.id_empleado = c.id_empleado
                WHERE se.id_sede = %s AND se.fecha_salida IS NULL
            """, (sid,)) or 0,
            "dispositivos": db.scalar("""
                SELECT COUNT(DISTINCT ak.id_dispositivo_gps)
                FROM asignacion_kit ak
                JOIN sede_pacientes sp ON ak.id_paciente = sp.id_paciente
                WHERE sp.id_sede = %s AND sp.fecha_salida IS NULL
                  AND ak.fecha_fin IS NULL
            """, (sid,)) or 0,
            "alertas_activas": db.scalar("""
                SELECT COUNT(*) FROM alertas a
                JOIN sede_pacientes sp ON a.id_paciente = sp.id_paciente
                WHERE sp.id_sede = %s AND sp.fecha_salida IS NULL AND a.estatus = 'Activa'
            """, (sid,)) or 0,
        })

    alertas = db.query("""
        SELECT a.tipo_alerta,
               a.estatus    AS estatus_alerta,
               a.fecha_hora AS fecha_hora_lectura,
               p.nombre || ' ' || p.apellido_p AS paciente,
               sp.id_sede   AS id_sucursal,
               s.nombre_sede AS nombre_sucursal
        FROM alertas a
        JOIN pacientes p ON a.id_paciente = p.id_paciente
        LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                                   AND sp.fecha_salida IS NULL
        LEFT JOIN sedes s ON sp.id_sede = s.id_sede
        ORDER BY a.fecha_hora DESC
        LIMIT 10
    """)

    medicamentos_criticos = db.query("""
        SELECT im.GTIN, im.stock_actual, im.stock_minimo,
               m.nombre_medicamento, s.nombre_sede
        FROM inventario_medicinas im
        JOIN medicamentos m ON im.GTIN = m.GTIN
        JOIN sedes s        ON im.id_sede = s.id_sede
        WHERE im.stock_actual < im.stock_minimo
    """)

    suministros_pendientes = db.query("""
        SELECT su.id_suministro, su.fecha_entrega, su.estado,
               fp.nombre AS farmacia, s.nombre_sede
        FROM suministros su
        JOIN farmacias_proveedoras fp ON su.id_farmacia = fp.id_farmacia
        JOIN sedes s                  ON su.id_sede     = s.id_sede
        WHERE su.estado = 'Pendiente'
        ORDER BY su.fecha_entrega
    """)

    visitas_hoy = db.query("""
        SELECT v.id_visita, v.fecha_entrada, v.hora_entrada,
               p.nombre || ' ' || p.apellido_p AS paciente,
               vt.nombre || ' ' || vt.apellido_p AS visitante,
               s.nombre_sede AS nombre_sucursal
        FROM visitas v
        JOIN pacientes p  ON v.id_paciente  = p.id_paciente
        JOIN visitantes vt ON v.id_visitante = vt.id_visitante
        JOIN sedes s       ON v.id_sede      = s.id_sede
        WHERE v.fecha_entrada = CURRENT_DATE
        ORDER BY v.hora_entrada DESC
    """)

    return render_template(
        "dashboard.html",
        stats=stats,
        alertas=alertas,
        stats_por_sede=stats_por_sede,
        sucursales=sedes,
        medicamentos_criticos=medicamentos_criticos,
        suministros_pendientes=suministros_pendientes,
        visitas_hoy=visitas_hoy,
    )


# ═══════════════════════════════════════════════════════════════════════════════
# PACIENTES
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/pacientes")
@admin_requerido
def pacientes_lista():
    pacientes = db.query("""
        SELECT p.id_paciente,
               p.nombre      AS nombre_paciente,
               p.apellido_p  AS apellido_p_pac,
               p.apellido_m  AS apellido_m_pac,
               p.fecha_nacimiento,
               p.id_estado,
               ep.desc_estado,
               sp.id_sede    AS id_sucursal,
               s.nombre_sede AS nombre_sucursal
        FROM pacientes p
        JOIN estados_paciente ep ON p.id_estado = ep.id_estado
        LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                                   AND sp.fecha_salida IS NULL
        LEFT JOIN sedes s ON sp.id_sede = s.id_sede
        WHERE p.id_estado != 3
        ORDER BY p.id_paciente
    """)
    sedes = db.query("SELECT * FROM sedes ORDER BY id_sede")
    return render_template("pacientes/list.html", pacientes=pacientes, sucursales=sedes)


@app.route("/pacientes/nuevo", methods=["GET", "POST"])
@admin_requerido
def pacientes_nuevo():
    estados = db.query("SELECT * FROM estados_paciente ORDER BY id_estado")
    sedes   = db.query("SELECT id_sede, nombre_sede FROM sedes ORDER BY nombre_sede")
    if request.method == "POST":
        try:
            id_pac     = int(request.form["id_paciente"])
            nombre     = request.form["nombre_paciente"].strip()
            apellido_p = request.form["apellido_p_pac"].strip()
            apellido_m = request.form["apellido_m_pac"].strip()
            fecha_nac  = request.form["fecha_nacimiento"]
            id_estado  = int(request.form["id_estado"])
            id_sede    = int(request.form["id_sede"])

            next_sp = db.scalar(
                "SELECT COALESCE(MAX(id_sede_paciente), 0) + 1 FROM sede_pacientes"
            )

            db.execute_many([
                ("""INSERT INTO pacientes
                        (id_paciente, nombre, apellido_p, apellido_m, fecha_nacimiento, id_estado)
                    VALUES (%s, %s, %s, %s, %s, %s)""",
                 (id_pac, nombre, apellido_p, apellido_m, fecha_nac, id_estado)),
                ("""INSERT INTO sede_pacientes
                        (id_sede_paciente, id_sede, id_paciente, fecha_ingreso, hora_ingreso)
                    VALUES (%s, %s, %s, CURRENT_DATE, CURRENT_TIME)""",
                 (next_sp, id_sede, id_pac)),
            ])

            flash("Paciente registrado correctamente.", "success")
            return redirect(url_for("pacientes_lista"))
        except Exception as e:
            flash(f"Error al registrar paciente: {e}", "error")

    return render_template("pacientes/form.html", paciente=None, estados=estados, sedes=sedes)


@app.route("/pacientes/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def pacientes_editar(id):
    estados = db.query("SELECT * FROM estados_paciente ORDER BY id_estado")
    paciente = db.one("""
        SELECT p.id_paciente,
               p.nombre     AS nombre_paciente,
               p.apellido_p AS apellido_p_pac,
               p.apellido_m AS apellido_m_pac,
               p.fecha_nacimiento,
               p.id_estado,
               ep.desc_estado
        FROM pacientes p
        JOIN estados_paciente ep ON p.id_estado = ep.id_estado
        WHERE p.id_paciente = %s
    """, (id,))

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

            db.execute("""
                UPDATE pacientes
                SET nombre = %s, apellido_p = %s, apellido_m = %s,
                    fecha_nacimiento = %s, id_estado = %s
                WHERE id_paciente = %s
            """, (nombre, apellido_p, apellido_m, fecha_nac, id_estado, id))

            flash("Paciente actualizado correctamente.", "success")
            return redirect(url_for("pacientes_lista"))
        except Exception as e:
            flash(f"Error al actualizar paciente: {e}", "error")

    return render_template("pacientes/form.html", paciente=paciente, estados=estados, sedes=[])


@app.route("/pacientes/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def pacientes_eliminar(id):
    try:
        db.execute("UPDATE pacientes SET id_estado = 3 WHERE id_paciente = %s", (id,))
        flash("Paciente dado de baja correctamente.", "success")
    except Exception as e:
        flash(f"Error al dar de baja: {e}", "error")
    return redirect(url_for("pacientes_lista"))


@app.route("/pacientes/historial/<int:id>")
@admin_requerido
def pacientes_historial(id):
    paciente = db.one("""
        SELECT p.id_paciente,
               p.nombre     AS nombre_paciente,
               p.apellido_p AS apellido_p_pac,
               p.apellido_m AS apellido_m_pac,
               p.fecha_nacimiento,
               p.id_estado,
               ep.desc_estado
        FROM pacientes p
        JOIN estados_paciente ep ON p.id_estado = ep.id_estado
        WHERE p.id_paciente = %s
    """, (id,))

    if not paciente:
        flash("Paciente no encontrado.", "error")
        return redirect(url_for("pacientes_lista"))

    estado = {"desc_estado": paciente["desc_estado"]}

    enfermedades = db.query("""
        SELECT e.nombre_enfermedad,
               TO_CHAR(te.fecha_diag, 'YYYY-MM-DD') AS fecha_diag
        FROM tiene_enfermedad te
        JOIN enfermedades e ON te.id_enfermedad = e.id_enfermedad
        WHERE te.id_paciente = %s
    """, (id,))

    cuidadores = db.query("""
        SELECT e.nombre     AS nombre_cuidador,
               e.apellido_p AS apellido_p_cuid,
               e.apellido_m AS apellido_m_cuid,
               e.telefono   AS telefono_cuid,
               TO_CHAR(ac.fecha_inicio, 'YYYY-MM-DD') AS fecha_asig_cuidador
        FROM asignacion_cuidador ac
        JOIN cuidadores c ON ac.id_cuidador = c.id_empleado
        JOIN empleados e  ON c.id_empleado  = e.id_empleado
        WHERE ac.id_paciente = %s AND ac.fecha_fin IS NULL
    """, (id,))

    contactos = db.query("""
        SELECT ce.nombre, ce.relacion, ce.telefono, pc.prioridad
        FROM paciente_contactos pc
        JOIN contactos_emergencia ce ON pc.id_contacto = ce.id_contacto
        WHERE pc.id_paciente = %s
        ORDER BY pc.prioridad
    """, (id,))

    kit = db.one("""
        SELECT ak.id_monitoreo,
               gps.id_serial  AS codigo_gps,
               TO_CHAR(ak.fecha_entrega, 'YYYY-MM-DD') AS fecha_entrega
        FROM asignacion_kit ak
        JOIN dispositivos gps ON ak.id_dispositivo_gps = gps.id_dispositivo
        WHERE ak.id_paciente = %s AND ak.fecha_fin IS NULL
        LIMIT 1
    """, (id,))

    historial_sedes = db.query("""
        SELECT sp.id_sede_paciente,
               sp.id_sede,
               s.nombre_sede,
               TO_CHAR(sp.fecha_ingreso, 'YYYY-MM-DD') AS fecha_ingreso,
               sp.hora_ingreso,
               TO_CHAR(sp.fecha_salida,  'YYYY-MM-DD') AS fecha_salida,
               sp.hora_salida
        FROM sede_pacientes sp
        JOIN sedes s ON sp.id_sede = s.id_sede
        WHERE sp.id_paciente = %s
        ORDER BY sp.fecha_ingreso DESC
    """, (id,))

    sede_actual_id = next(
        (r["id_sede"] for r in historial_sedes if r["fecha_salida"] is None),
        None
    )

    sedes_disponibles = db.query("""
        SELECT id_sede, nombre_sede FROM sedes
        WHERE id_sede != %s
        ORDER BY nombre_sede
    """, (sede_actual_id or 0,))

    alertas_paciente = db.query("""
        SELECT a.id_alerta, a.tipo_alerta, a.estatus,
               TO_CHAR(a.fecha_hora, 'YYYY-MM-DD') AS fecha,
               TO_CHAR(a.fecha_hora, 'HH24:MI')    AS hora
        FROM alertas a
        WHERE a.id_paciente = %s
        ORDER BY a.fecha_hora DESC
    """, (id,))

    visitas = db.query("""
        SELECT v.id_visita,
               TO_CHAR(v.fecha_entrada, 'YYYY-MM-DD') AS fecha_entrada,
               v.hora_entrada, v.fecha_salida, v.hora_salida,
               vt.nombre || ' ' || vt.apellido_p AS visitante,
               vt.relacion
        FROM visitas v
        JOIN visitantes vt ON v.id_visitante = vt.id_visitante
        WHERE v.id_paciente = %s
        ORDER BY v.fecha_entrada DESC
    """, (id,))

    entregas = db.query("""
        SELECT ee.id_entrega, ee.descripcion, ee.estado,
               TO_CHAR(ee.fecha_recepcion, 'YYYY-MM-DD') AS fecha,
               ee.hora_recepcion,
               vt.nombre || ' ' || vt.apellido_p AS visitante
        FROM entregas_externas ee
        JOIN visitantes vt ON ee.id_visitante = vt.id_visitante
        WHERE ee.id_paciente = %s
        ORDER BY ee.fecha_recepcion DESC
    """, (id,))

    nfc_asignacion = db.one("""
        SELECT an.id_asignacion, d.id_serial AS serial_nfc,
               TO_CHAR(an.fecha_inicio, 'YYYY-MM-DD') AS fecha_inicio
        FROM asignacion_nfc an
        JOIN dispositivos d ON an.id_dispositivo = d.id_dispositivo
        WHERE an.id_paciente = %s AND an.fecha_fin IS NULL
    """, (id,))

    nfc_disponibles = db.query("""
        SELECT d.id_dispositivo, d.id_serial, d.modelo
        FROM dispositivos d
        WHERE d.tipo = 'NFC' AND d.estado = 'Activo'
          AND NOT EXISTS (
              SELECT 1 FROM asignacion_nfc an
              WHERE an.id_dispositivo = d.id_dispositivo AND an.fecha_fin IS NULL
          )
        ORDER BY d.id_serial
    """)

    enfermedades_disponibles = db.query("""
        SELECT id_enfermedad, nombre_enfermedad FROM enfermedades
        WHERE id_enfermedad NOT IN (
            SELECT id_enfermedad FROM tiene_enfermedad WHERE id_paciente = %s
        )
        ORDER BY nombre_enfermedad
    """, (id,))

    gps_disponibles = db.query("""
        SELECT d.id_dispositivo, d.id_serial, d.modelo
        FROM dispositivos d
        WHERE d.tipo = 'GPS' AND d.estado = 'Activo'
          AND NOT EXISTS (
              SELECT 1 FROM asignacion_kit ak
              WHERE ak.id_dispositivo_gps = d.id_dispositivo AND ak.fecha_fin IS NULL
          )
        ORDER BY d.id_serial
    """)

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
    )


@app.route("/pacientes/<int:id>/reporte-pdf")
@admin_requerido
def pacientes_reporte_pdf(id):
    from pdf_report import generate_patient_report
    from flask import send_file
    paciente = db.one(
        "SELECT nombre, apellido_p FROM pacientes WHERE id_paciente = %s", (id,)
    )
    if not paciente:
        flash("Paciente no encontrado.", "error")
        return redirect(url_for("pacientes_lista"))
    buf = generate_patient_report(id)
    nombre_archivo = (
        f"reporte_{paciente['nombre'].lower()}_{paciente['apellido_p'].lower()}_{id}.pdf"
    )
    return send_file(buf, mimetype="application/pdf",
                     as_attachment=True, download_name=nombre_archivo)


@app.route("/pacientes/<int:id>/transferir-sede", methods=["POST"])
@admin_requerido
def pacientes_transferir_sede(id):
    try:
        nueva_sede_id = int(request.form["nueva_sede_id"])

        activos = db.query("""
            SELECT id_sede_paciente, id_sede
            FROM sede_pacientes
            WHERE id_paciente = %s AND fecha_salida IS NULL
        """, (id,))

        if len(activos) > 1:
            raise Exception(
                f"Integridad comprometida: el paciente tiene {len(activos)} "
                "asignaciones activas simultáneas. Corrija manualmente."
            )

        if activos and activos[0]["id_sede"] == nueva_sede_id:
            flash("El paciente ya está asignado a esa sede.", "error")
            return redirect(url_for("pacientes_historial", id=id))

        ops = []
        if activos:
            ops.append(("""
                UPDATE sede_pacientes
                SET fecha_salida = CURRENT_DATE,
                    hora_salida  = CURRENT_TIME
                WHERE id_paciente = %s AND fecha_salida IS NULL
            """, (id,)))

        ops.append(("""
            INSERT INTO sede_pacientes
                (id_sede_paciente, id_sede, id_paciente, fecha_ingreso, hora_ingreso)
            SELECT (SELECT COALESCE(MAX(id_sede_paciente), 0) + 1 FROM sede_pacientes),
                   %s, %s, CURRENT_DATE, CURRENT_TIME
        """, (nueva_sede_id, id)))

        db.execute_many(ops)

        sede_nombre = db.scalar(
            "SELECT nombre_sede FROM sedes WHERE id_sede = %s", (nueva_sede_id,)
        )
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
        db.execute("""
            INSERT INTO tiene_enfermedad (id_paciente, id_enfermedad, fecha_diag)
            VALUES (%s, %s, %s)
        """, (id, id_enfermedad, fecha_diag))
        flash("Enfermedad agregada correctamente.", "success")
    except Exception as e:
        flash(f"Error al agregar enfermedad: {e}", "error")
    return redirect(url_for("pacientes_historial", id=id))


@app.route("/pacientes/<int:id>/quitar-enfermedad", methods=["POST"])
@admin_requerido
def pacientes_quitar_enfermedad(id):
    try:
        id_enfermedad = int(request.form["id_enfermedad"])
        db.execute("""
            DELETE FROM tiene_enfermedad
            WHERE id_paciente = %s AND id_enfermedad = %s
        """, (id, id_enfermedad))
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

        next_id   = db.scalar(
            "SELECT COALESCE(MAX(id_contacto), 0) + 1 FROM contactos_emergencia"
        )
        next_prio = db.scalar(
            "SELECT COALESCE(MAX(prioridad), 0) + 1 FROM paciente_contactos WHERE id_paciente = %s",
            (id,)
        )

        db.execute_many([
            ("""INSERT INTO contactos_emergencia
                    (id_contacto, nombre, apellido_p, apellido_m, telefono, relacion, email, pin_acceso)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
             (next_id, nombre, apellido_p, apellido_m, telefono, relacion, email, pin_acceso)),
            ("""INSERT INTO paciente_contactos (id_paciente, id_contacto, prioridad)
                VALUES (%s, %s, %s)""",
             (id, next_id, next_prio)),
        ])

        flash("Contacto de emergencia agregado correctamente.", "success")
    except Exception as e:
        flash(f"Error al agregar contacto: {e}", "error")
    return redirect(url_for("pacientes_historial", id=id))


@app.route("/pacientes/<int:id>/asignar-kit", methods=["POST"])
@admin_requerido
def pacientes_asignar_kit(id):
    try:
        id_gps  = int(request.form["id_dispositivo_gps"])
        next_id = db.scalar(
            "SELECT COALESCE(MAX(id_monitoreo), 0) + 1 FROM asignacion_kit"
        )
        db.execute("""
            INSERT INTO asignacion_kit
                (id_monitoreo, id_paciente, id_dispositivo_gps, fecha_entrega)
            VALUES (%s, %s, %s, CURRENT_DATE)
        """, (next_id, id, id_gps))
        flash("Kit GPS asignado correctamente.", "success")
    except Exception as e:
        flash(f"Error al asignar kit GPS: {e}", "error")
    return redirect(url_for("pacientes_historial", id=id))


# ═══════════════════════════════════════════════════════════════════════════════
# CUIDADORES
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/cuidadores")
@admin_requerido
def cuidadores_lista():
    cuidadores = db.query("""
        SELECT e.id_empleado  AS id_cuidador,
               e.nombre       AS nombre_cuidador,
               e.apellido_p   AS apellido_p_cuid,
               e.apellido_m   AS apellido_m_cuid,
               e.telefono     AS telefono_cuid,
               se.id_sede     AS id_sucursal,
               s.nombre_sede  AS nombre_sucursal
        FROM cuidadores c
        JOIN empleados e ON c.id_empleado = e.id_empleado
        LEFT JOIN sede_empleados se ON e.id_empleado = se.id_empleado
                                   AND se.fecha_salida IS NULL
        LEFT JOIN sedes s ON se.id_sede = s.id_sede
        ORDER BY e.id_empleado
    """)
    return render_template("cuidadores/list.html",
                           cuidadores=cuidadores,
                           sucursales=db.query("SELECT * FROM sedes ORDER BY id_sede"))


@app.route("/cuidadores/nuevo", methods=["GET", "POST"])
@admin_requerido
def cuidadores_nuevo():
    if request.method == "POST":
        try:
            id_cuid    = int(request.form["id_cuidador"])
            nombre     = request.form["nombre_cuidador"].strip()
            apellido_p = request.form["apellido_p_cuid"].strip()
            apellido_m = request.form["apellido_m_cuid"].strip()
            telefono   = request.form.get("telefono_cuid", "").strip() or None
            curp       = request.form["curp_pasaporte"].strip()

            db.execute_many([
                ("""
                    INSERT INTO empleados
                        (id_empleado, nombre, apellido_p, apellido_m, CURP_pasaporte, telefono)
                    VALUES (%s, %s, %s, %s, %s, %s)
                """, (id_cuid, nombre, apellido_p, apellido_m, curp, telefono)),
                ("""
                    INSERT INTO cuidadores (id_empleado)
                    VALUES (%s)
                """, (id_cuid,)),
            ])

            flash("Cuidador registrado correctamente.", "success")
            return redirect(url_for("cuidadores_lista"))
        except Exception as e:
            flash(f"Error al registrar cuidador: {e}", "error")

    return render_template("cuidadores/form.html", cuidador=None)


@app.route("/cuidadores/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def cuidadores_editar(id):
    cuidador = db.one("""
        SELECT e.id_empleado  AS id_cuidador,
               e.nombre       AS nombre_cuidador,
               e.apellido_p   AS apellido_p_cuid,
               e.apellido_m   AS apellido_m_cuid,
               e.telefono     AS telefono_cuid,
               e.CURP_pasaporte AS curp_pasaporte
        FROM cuidadores c
        JOIN empleados e ON c.id_empleado = e.id_empleado
        WHERE c.id_empleado = %s
    """, (id,))

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

            db.execute("""
                UPDATE empleados
                SET nombre = %s, apellido_p = %s, apellido_m = %s,
                    telefono = %s, CURP_pasaporte = %s
                WHERE id_empleado = %s
            """, (nombre, apellido_p, apellido_m, telefono, curp, id))

            flash("Cuidador actualizado correctamente.", "success")
            return redirect(url_for("cuidadores_lista"))
        except Exception as e:
            flash(f"Error al actualizar cuidador: {e}", "error")

    return render_template("cuidadores/form.html", cuidador=cuidador)


@app.route("/cuidadores/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def cuidadores_eliminar(id):
    try:
        db.execute_many([
            ("DELETE FROM cuidadores WHERE id_empleado = %s", (id,)),
            ("DELETE FROM empleados  WHERE id_empleado = %s", (id,)),
        ])
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
    turnos = db.query("""
        SELECT tc.id_turno, tc.hora_inicio, tc.hora_fin, tc.activo,
               tc.lunes, tc.martes, tc.miercoles, tc.jueves,
               tc.viernes, tc.sabado, tc.domingo,
               z.nombre_zona, tc.id_zona,
               e.nombre || ' ' || e.apellido_p AS nombre_cuidador,
               tc.id_cuidador
        FROM turno_cuidador tc
        JOIN zonas z      ON tc.id_zona     = z.id_zona
        JOIN cuidadores c ON tc.id_cuidador = c.id_empleado
        JOIN empleados e  ON c.id_empleado  = e.id_empleado
        ORDER BY z.nombre_zona, tc.hora_inicio
    """)
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

            db.execute("""
                INSERT INTO turno_cuidador
                    (id_turno, id_cuidador, id_zona, hora_inicio, hora_fin,
                     lunes, martes, miercoles, jueves, viernes, sabado, domingo, activo)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,TRUE)
            """, (id_turno, id_cuidador, id_zona, hora_inicio, hora_fin,
                  dias["lunes"], dias["martes"], dias["miercoles"], dias["jueves"],
                  dias["viernes"], dias["sabado"], dias["domingo"]))

            flash("Turno registrado correctamente.", "success")
            return redirect(url_for("turnos_lista"))
        except Exception as e:
            flash(f"Error al registrar turno: {e}", "error")

    cuidadores = db.query("""
        SELECT c.id_empleado AS id_cuidador,
               e.nombre || ' ' || e.apellido_p AS nombre
        FROM cuidadores c JOIN empleados e ON c.id_empleado = e.id_empleado
        ORDER BY e.nombre
    """)
    zonas_list = db.query("SELECT id_zona, nombre_zona FROM zonas ORDER BY nombre_zona")
    return render_template("turnos/form.html", turno=None,
                           cuidadores=cuidadores, zonas=zonas_list)


@app.route("/turnos/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def turnos_editar(id):
    turno = db.one("""
        SELECT tc.*, z.nombre_zona,
               e.nombre || ' ' || e.apellido_p AS nombre_cuidador
        FROM turno_cuidador tc
        JOIN zonas z      ON tc.id_zona     = z.id_zona
        JOIN cuidadores c ON tc.id_cuidador = c.id_empleado
        JOIN empleados e  ON c.id_empleado  = e.id_empleado
        WHERE tc.id_turno = %s
    """, (id,))
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

            db.execute("""
                UPDATE turno_cuidador
                SET id_cuidador = %s, id_zona = %s, hora_inicio = %s, hora_fin = %s,
                    lunes = %s, martes = %s, miercoles = %s, jueves = %s,
                    viernes = %s, sabado = %s, domingo = %s, activo = %s
                WHERE id_turno = %s
            """, (id_cuidador, id_zona, hora_inicio, hora_fin,
                  dias["lunes"], dias["martes"], dias["miercoles"], dias["jueves"],
                  dias["viernes"], dias["sabado"], dias["domingo"], activo, id))

            flash("Turno actualizado correctamente.", "success")
            return redirect(url_for("turnos_lista"))
        except Exception as e:
            flash(f"Error al actualizar turno: {e}", "error")

    cuidadores = db.query("""
        SELECT c.id_empleado AS id_cuidador,
               e.nombre || ' ' || e.apellido_p AS nombre
        FROM cuidadores c JOIN empleados e ON c.id_empleado = e.id_empleado
        ORDER BY e.nombre
    """)
    zonas_list = db.query("SELECT id_zona, nombre_zona FROM zonas ORDER BY nombre_zona")
    return render_template("turnos/form.html", turno=turno,
                           cuidadores=cuidadores, zonas=zonas_list)


@app.route("/turnos/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def turnos_eliminar(id):
    try:
        db.execute("DELETE FROM turno_cuidador WHERE id_turno = %s", (id,))
        flash("Turno eliminado correctamente.", "success")
    except Exception as e:
        flash(f"Error al eliminar turno: {e}", "error")
    return redirect(url_for("turnos_lista"))


# ═══════════════════════════════════════════════════════════════════════════════
# ALERTAS
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/alertas")
@admin_requerido
def alertas():
    alertas_list = db.query("""
        SELECT a.id_alerta, a.tipo_alerta, a.estatus, a.fecha_hora,
               COALESCE(
                   p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m,
                   '— Zona: ' || z.nombre_zona,
                   '—'
               ) AS paciente,
               COALESCE(s.nombre_sede, sz.nombre_sede, '—') AS nombre_sucursal,
               aeo.tipo_evento,
               aeo.regla_disparada,
               -- Priority contact for this patient
               ce.nombre || ' ' || ce.apellido_p AS contacto_prioritario,
               ce.telefono AS telefono_contacto
        FROM alertas a
        LEFT JOIN pacientes p       ON a.id_paciente = p.id_paciente
        LEFT JOIN zonas z           ON a.id_zona = z.id_zona
        LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                                   AND sp.fecha_salida IS NULL
        LEFT JOIN sedes s           ON sp.id_sede = s.id_sede
        LEFT JOIN sede_zonas szr    ON a.id_zona = szr.id_zona
        LEFT JOIN sedes sz          ON szr.id_sede = sz.id_sede
        LEFT JOIN alerta_evento_origen aeo ON aeo.id_alerta = a.id_alerta
        LEFT JOIN (
            SELECT pc.id_paciente, pc.id_contacto
            FROM paciente_contactos pc
            WHERE pc.prioridad = (
                SELECT MIN(pc2.prioridad)
                FROM paciente_contactos pc2
                WHERE pc2.id_paciente = pc.id_paciente
            )
        ) pc_top ON pc_top.id_paciente = a.id_paciente
        LEFT JOIN contactos_emergencia ce ON ce.id_contacto = pc_top.id_contacto
        ORDER BY a.fecha_hora DESC
    """)
    return render_template("alertas.html", alertas=alertas_list)


@app.route("/alertas/nueva", methods=["GET", "POST"])
@admin_requerido
def alertas_nueva():
    pacientes   = db.query("SELECT id_paciente, nombre || ' ' || apellido_p AS nombre FROM pacientes WHERE id_estado != 3 ORDER BY nombre")
    tipos       = db.query("SELECT tipo_alerta FROM cat_tipo_alerta ORDER BY tipo_alerta")

    if request.method == "POST":
        try:
            id_paciente = request.form.get("id_paciente") or None
            if id_paciente:
                id_paciente = int(id_paciente)
            tipo_alerta = request.form["tipo_alerta"]
            fecha_hora  = request.form["fecha_hora"]

            id_alerta = db.scalar("SELECT COALESCE(MAX(id_alerta), 0) + 1 FROM alertas")
            db.execute("""
                INSERT INTO alertas (id_alerta, id_paciente, tipo_alerta, fecha_hora, estatus)
                VALUES (%s, %s, %s, %s, 'Activa')
            """, (id_alerta, id_paciente, tipo_alerta, fecha_hora))

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
        db.execute("UPDATE alertas SET estatus = 'Atendida' WHERE id_alerta = %s", (id,))
        flash("Alerta marcada como atendida.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("alertas"))


@app.route("/alertas/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def alertas_eliminar(id):
    try:
        db.execute("DELETE FROM alertas WHERE id_alerta = %s", (id,))
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
    dispositivos_list = db.query("""
        SELECT d.id_dispositivo,
               d.id_serial AS codigo,
               d.tipo,
               d.modelo,
               d.estado    AS estatus,
               (
                   SELECT lg.nivel_bateria
                   FROM lecturas_gps lg
                   WHERE lg.id_dispositivo = d.id_dispositivo
                   ORDER BY lg.fecha_hora DESC
                   LIMIT 1
               ) AS bateria,
               COALESCE(
                   p.nombre || ' ' || p.apellido_p, '—'
               ) AS paciente,
               sp.id_sede  AS id_sucursal,
               COALESCE(s.nombre_sede, '—') AS nombre_sucursal
        FROM dispositivos d
        LEFT JOIN asignacion_kit ak
               ON d.id_dispositivo = ak.id_dispositivo_gps AND ak.fecha_fin IS NULL
        LEFT JOIN pacientes p ON ak.id_paciente = p.id_paciente
        LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                                   AND sp.fecha_salida IS NULL
        LEFT JOIN sedes s ON sp.id_sede = s.id_sede
        ORDER BY d.id_dispositivo
    """)
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

            db.execute("""
                INSERT INTO dispositivos (id_dispositivo, id_serial, tipo, modelo, estado)
                VALUES (%s, %s, %s, %s, 'Activo')
            """, (id_disp, id_serial, tipo, modelo))

            flash("Dispositivo registrado correctamente.", "success")
            return redirect(url_for("dispositivos"))
        except Exception as e:
            flash(f"Error al registrar dispositivo: {e}", "error")

    return render_template("dispositivos_form.html")


@app.route("/dispositivos/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def dispositivos_editar(id):
    disp = db.one("SELECT * FROM dispositivos WHERE id_dispositivo = %s", (id,))
    if not disp:
        flash("Dispositivo no encontrado.", "error")
        return redirect(url_for("dispositivos"))

    if request.method == "POST":
        try:
            id_serial = request.form["id_serial"].strip()
            tipo      = request.form["tipo"].strip()
            modelo    = request.form["modelo"].strip()
            estado    = request.form["estado"].strip()

            db.execute("""
                UPDATE dispositivos
                SET id_serial = %s, tipo = %s, modelo = %s, estado = %s
                WHERE id_dispositivo = %s
            """, (id_serial, tipo, modelo, estado, id))

            flash("Dispositivo actualizado correctamente.", "success")
            return redirect(url_for("dispositivos"))
        except Exception as e:
            flash(f"Error al actualizar dispositivo: {e}", "error")

    return render_template("dispositivos_form.html", disp=disp)


@app.route("/dispositivos/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def dispositivos_eliminar(id):
    try:
        db.execute("DELETE FROM dispositivos WHERE id_dispositivo = %s", (id,))
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
    zonas_list = db.query("""
        SELECT z.id_zona, z.nombre_zona, z.radio_metros,
               z.latitud_centro, z.longitud_centro,
               s.id_sede    AS id_sucursal,
               COALESCE(s.nombre_sede, '—') AS nombre_sucursal,
               -- Pacientes activos en esta sede (nombres concatenados)
               COALESCE(
                   (SELECT STRING_AGG(p.nombre || ' ' || p.apellido_p, ', ' ORDER BY p.nombre)
                    FROM pacientes p
                    JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente
                    WHERE sp.id_sede = sz.id_sede
                      AND sp.fecha_salida IS NULL
                      AND p.id_estado != 3),
                   '—'
               ) AS pacientes_en_zona,
               -- Contacto de mayor prioridad de la sede (para notificación)
               COALESCE(
                   (SELECT ce.nombre || ' ' || ce.apellido_p || ' · ' || ce.telefono
                    FROM paciente_contactos pc
                    JOIN contactos_emergencia ce ON ce.id_contacto = pc.id_contacto
                    JOIN sede_pacientes sp ON sp.id_paciente = pc.id_paciente
                    WHERE sp.id_sede = sz.id_sede
                      AND sp.fecha_salida IS NULL
                    ORDER BY pc.prioridad ASC
                    LIMIT 1),
                   '—'
               ) AS notificar_a
        FROM zonas z
        LEFT JOIN sede_zonas sz ON z.id_zona = sz.id_zona
        LEFT JOIN sedes s       ON sz.id_sede = s.id_sede
        ORDER BY z.id_zona
    """)
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

            db.execute("""
                INSERT INTO zonas (nombre_zona, latitud_centro, longitud_centro, radio_metros)
                VALUES (%s, %s, %s, %s)
            """, (nombre_zona, latitud, longitud, radio))

            flash("Zona segura registrada correctamente.", "success")
            return redirect(url_for("zonas"))
        except Exception as e:
            flash(f"Error al registrar zona: {e}", "error")

    sedes = db.query("SELECT id_sede, nombre_sede FROM sedes ORDER BY id_sede")
    return render_template("zonas_form.html", zona=None, sedes=sedes)


@app.route("/zonas/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def zonas_editar(id):
    zona = db.one("SELECT * FROM zonas WHERE id_zona = %s", (id,))
    if not zona:
        flash("Zona no encontrada.", "error")
        return redirect(url_for("zonas"))

    if request.method == "POST":
        try:
            nombre_zona = request.form["nombre_zona"].strip()
            latitud     = float(request.form["latitud_centro"])
            longitud    = float(request.form["longitud_centro"])
            radio       = float(request.form["radio_metros"])

            db.execute("""
                UPDATE zonas
                SET nombre_zona = %s, latitud_centro = %s,
                    longitud_centro = %s, radio_metros = %s
                WHERE id_zona = %s
            """, (nombre_zona, latitud, longitud, radio, id))

            flash("Zona actualizada correctamente.", "success")
            return redirect(url_for("zonas"))
        except Exception as e:
            flash(f"Error al actualizar zona: {e}", "error")

    sedes = db.query("SELECT id_sede, nombre_sede FROM sedes ORDER BY id_sede")
    return render_template("zonas_form.html", zona=zona, sedes=sedes)


@app.route("/zonas/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def zonas_eliminar(id):
    try:
        db.execute("DELETE FROM zonas WHERE id_zona = %s", (id,))
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
    inventario = db.query("""
        SELECT im.GTIN, im.stock_actual, im.stock_minimo,
               m.nombre_medicamento, s.id_sede, s.nombre_sede
        FROM inventario_medicinas im
        JOIN medicamentos m ON im.GTIN    = m.GTIN
        JOIN sedes s        ON im.id_sede = s.id_sede
        ORDER BY s.id_sede, m.nombre_medicamento
    """)
    criticos = [row for row in inventario if row["stock_actual"] < row["stock_minimo"]]

    suministros = db.query("""
        SELECT su.id_suministro,
               TO_CHAR(su.fecha_entrega, 'YYYY-MM-DD') AS fecha_entrega,
               su.estado,
               fp.nombre AS farmacia,
               s.nombre_sede,
               COALESCE(STRING_AGG(m.nombre_medicamento, ' · '
                        ORDER BY m.nombre_medicamento), '—') AS medicamentos
        FROM suministros su
        JOIN farmacias_proveedoras fp ON su.id_farmacia = fp.id_farmacia
        JOIN sedes s                  ON su.id_sede     = s.id_sede
        LEFT JOIN suministro_medicinas sm ON su.id_suministro = sm.id_suministro
        LEFT JOIN medicamentos m          ON sm.GTIN          = m.GTIN
        GROUP BY su.id_suministro, su.fecha_entrega, su.estado,
                 fp.nombre, s.nombre_sede
        ORDER BY su.id_suministro DESC
    """)

    farmacias     = db.query("SELECT * FROM farmacias_proveedoras ORDER BY id_farmacia")
    medicamentos  = db.query("SELECT GTIN, nombre_medicamento FROM medicamentos ORDER BY nombre_medicamento")
    sedes         = db.query("SELECT id_sede, nombre_sede FROM sedes ORDER BY id_sede")

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

        db.execute("""
            UPDATE inventario_medicinas
            SET stock_actual = %s
            WHERE GTIN = %s AND id_sede = %s
        """, (stock_nuevo, gtin, id_sede))

        flash("Stock actualizado correctamente.", "success")
    except Exception as e:
        flash(f"Error al ajustar stock: {e}", "error")
    return redirect(url_for("farmacia"))


@app.route("/farmacia/suministro/nuevo", methods=["GET", "POST"])
@admin_requerido
def farmacia_suministro_nuevo():
    farmacias    = db.query("SELECT * FROM farmacias_proveedoras ORDER BY id_farmacia")
    sedes        = db.query("SELECT id_sede, nombre_sede FROM sedes ORDER BY id_sede")
    medicamentos = db.query("SELECT GTIN, nombre_medicamento FROM medicamentos ORDER BY nombre_medicamento")

    if request.method == "POST":
        try:
            id_sum      = int(request.form["id_suministro"])
            id_farmacia = int(request.form["id_farmacia"])
            id_sede     = int(request.form["id_sede"])
            fecha       = request.form["fecha_entrega"]
            estado      = request.form.get("estado", "Pendiente")
            gtins       = request.form.getlist("GTIN[]")
            cantidades  = request.form.getlist("cantidad[]")

            if not any(g.strip() for g in gtins):
                flash("Debe agregar al menos un medicamento a la orden.", "error")
                raise ValueError("sin_lineas")

            db.execute("""
                INSERT INTO suministros (id_suministro, id_farmacia, id_sede, fecha_entrega, estado)
                VALUES (%s, %s, %s, %s, %s)
            """, (id_sum, id_farmacia, id_sede, fecha, estado))

            for gtin, cant in zip(gtins, cantidades):
                if not gtin.strip():
                    continue
                db.execute("""
                    INSERT INTO suministro_medicinas (id_suministro, GTIN, cantidad)
                    VALUES (%s, %s, %s)
                """, (id_sum, gtin.strip(), int(cant)))

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
    suministro = db.one("""
        SELECT su.id_suministro,
               TO_CHAR(su.fecha_entrega, 'YYYY-MM-DD') AS fecha_entrega,
               su.hora_entrega,
               su.estado,
               fp.nombre AS farmacia,
               fp.telefono AS farmacia_tel,
               s.nombre_sede,
               s.id_sede
        FROM suministros su
        JOIN farmacias_proveedoras fp ON su.id_farmacia = fp.id_farmacia
        JOIN sedes s                  ON su.id_sede     = s.id_sede
        WHERE su.id_suministro = %s
    """, (id,))

    if not suministro:
        flash("Orden no encontrada.", "error")
        return redirect(url_for("farmacia"))

    lineas = db.query("""
        SELECT sm.GTIN, sm.cantidad,
               m.nombre_medicamento,
               im.stock_actual,
               im.stock_minimo
        FROM suministro_medicinas sm
        JOIN medicamentos m ON sm.GTIN = m.GTIN
        LEFT JOIN inventario_medicinas im ON sm.GTIN = im.GTIN AND im.id_sede = %s
        ORDER BY m.nombre_medicamento
    """, (suministro["id_sede"],))

    estados = db.query("SELECT estado FROM cat_estado_suministro ORDER BY estado")

    return render_template(
        "farmacia_suministro_detalle.html",
        suministro=suministro,
        lineas=lineas,
        estados=estados,
        medicamentos=db.query("SELECT GTIN, nombre_medicamento FROM medicamentos ORDER BY nombre_medicamento"),
    )


@app.route("/farmacia/suministro/<int:id>/estado", methods=["POST"])
@admin_requerido
def farmacia_suministro_estado(id):
    try:
        nuevo_estado = request.form["estado"]
        db.execute(
            "UPDATE suministros SET estado = %s WHERE id_suministro = %s",
            (nuevo_estado, id),
        )
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
        db.execute("""
            INSERT INTO suministro_medicinas (id_suministro, GTIN, cantidad)
            VALUES (%s, %s, %s)
            ON CONFLICT (id_suministro, GTIN)
            DO UPDATE SET cantidad = suministro_medicinas.cantidad + EXCLUDED.cantidad
        """, (id, gtin, cantidad))
        flash("Medicamento agregado a la orden.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("farmacia_suministro_detalle", id=id))


@app.route("/farmacia/suministro/<int:id>/eliminar", methods=["POST"])
@admin_requerido
def farmacia_suministro_eliminar(id):
    try:
        db.execute("DELETE FROM suministros WHERE id_suministro = %s", (id,))
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
    visitas_hoy = db.query("""
        SELECT v.id_visita,
               TO_CHAR(v.fecha_entrada, 'YYYY-MM-DD') AS fecha_entrada,
               v.hora_entrada, v.fecha_salida, v.hora_salida,
               p.nombre || ' ' || p.apellido_p AS paciente,
               vt.nombre || ' ' || vt.apellido_p AS visitante,
               vt.relacion,
               v.id_sede AS id_sucursal,
               s.nombre_sede AS nombre_sucursal
        FROM visitas v
        JOIN pacientes p   ON v.id_paciente  = p.id_paciente
        JOIN visitantes vt ON v.id_visitante = vt.id_visitante
        JOIN sedes s       ON v.id_sede      = s.id_sede
        WHERE v.fecha_entrada = CURRENT_DATE
        ORDER BY v.hora_entrada DESC
    """)

    visitas_hist = db.query("""
        SELECT v.id_visita,
               TO_CHAR(v.fecha_entrada, 'YYYY-MM-DD') AS fecha_entrada,
               v.hora_entrada, v.fecha_salida, v.hora_salida,
               p.nombre || ' ' || p.apellido_p AS paciente,
               vt.nombre || ' ' || vt.apellido_p AS visitante,
               vt.relacion,
               v.id_sede AS id_sucursal,
               s.nombre_sede AS nombre_sucursal
        FROM visitas v
        JOIN pacientes p   ON v.id_paciente  = p.id_paciente
        JOIN visitantes vt ON v.id_visitante = vt.id_visitante
        JOIN sedes s       ON v.id_sede      = s.id_sede
        WHERE v.fecha_entrada < CURRENT_DATE
        ORDER BY v.fecha_entrada DESC
        LIMIT 50
    """)

    entregas = db.query("""
        SELECT ee.id_entrega, ee.descripcion, ee.estado,
               TO_CHAR(ee.fecha_recepcion, 'YYYY-MM-DD') AS fecha,
               ee.hora_recepcion,
               p.nombre  || ' ' || p.apellido_p  AS paciente,
               vt.nombre || ' ' || vt.apellido_p AS visitante
        FROM entregas_externas ee
        JOIN pacientes p   ON ee.id_paciente  = p.id_paciente
        JOIN visitantes vt ON ee.id_visitante = vt.id_visitante
        ORDER BY ee.fecha_recepcion DESC
        LIMIT 30
    """)

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
    pacientes   = db.query("SELECT id_paciente, nombre || ' ' || apellido_p AS nombre FROM pacientes WHERE id_estado != 3 ORDER BY nombre")
    visitantes  = db.query("SELECT id_visitante, nombre || ' ' || apellido_p AS nombre, relacion FROM visitantes ORDER BY nombre")
    sedes       = db.query("SELECT id_sede, nombre_sede FROM sedes ORDER BY id_sede")

    if request.method == "POST":
        try:
            id_visita   = int(request.form["id_visita"])
            id_paciente = int(request.form["id_paciente"])
            id_visitante= int(request.form["id_visitante"])
            id_sede     = int(request.form["id_sede"])
            fecha       = request.form["fecha_entrada"]
            hora        = request.form["hora_entrada"]

            db.execute("""
                INSERT INTO visitas (id_visita, id_paciente, id_visitante, id_sede, fecha_entrada, hora_entrada)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (id_visita, id_paciente, id_visitante, id_sede, fecha, hora))

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
    recetas = db.query("""
        SELECT
            r.id_receta,
            r.estado,
            TO_CHAR(r.fecha, 'DD/MM/YYYY') AS fecha,
            p.id_paciente,
            p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_paciente,
            COALESCE(s.nombre_sede, '—') AS nombre_sede,
            COUNT(DISTINCT rm.id_detalle)  AS n_medicamentos,
            d.id_serial                    AS serial_nfc,
            TO_CHAR(rn.fecha_inicio_gestion, 'DD/MM/YYYY') AS nfc_desde,
            COUNT(ln.id_lectura_nfc)
                FILTER (WHERE ln.fecha_hora::date = CURRENT_DATE)               AS lecturas_hoy,
            COUNT(ln.id_lectura_nfc)
                FILTER (WHERE ln.fecha_hora::date = CURRENT_DATE
                          AND ln.resultado = 'Exitosa')                          AS exitosas_hoy
        FROM recetas r
        JOIN pacientes p
            ON p.id_paciente = r.id_paciente
        LEFT JOIN sede_pacientes sp
            ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
        LEFT JOIN sedes s
            ON s.id_sede = sp.id_sede
        LEFT JOIN receta_medicamentos rm
            ON rm.id_receta = r.id_receta
        LEFT JOIN receta_nfc rn
            ON rn.id_receta = r.id_receta AND rn.fecha_fin_gestion IS NULL
        LEFT JOIN dispositivos d
            ON d.id_dispositivo = rn.id_dispositivo
        LEFT JOIN lecturas_nfc ln
            ON ln.id_receta = r.id_receta
        WHERE p.id_estado != 3
        GROUP BY r.id_receta, r.estado, r.fecha, p.id_paciente, p.nombre, p.apellido_p,
                 p.apellido_m, s.nombre_sede, d.id_serial, rn.fecha_inicio_gestion
        ORDER BY r.fecha DESC
    """)
    return render_template("recetas.html", recetas=recetas)


@app.route("/recetas/nueva", methods=["GET", "POST"])
@admin_requerido
def recetas_nueva():
    pacientes = db.query("""
        SELECT p.id_paciente,
               p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_completo
        FROM pacientes p
        WHERE p.id_estado != 3
        ORDER BY p.apellido_p, p.nombre
    """)
    if request.method == "POST":
        try:
            id_paciente = int(request.form["id_paciente"])
            fecha       = request.form["fecha"]
            next_id     = db.scalar(
                "SELECT COALESCE(MAX(id_receta), 0) + 1 FROM recetas"
            )
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
    receta = db.one("""
        SELECT r.id_receta, r.estado, TO_CHAR(r.fecha, 'DD/MM/YYYY') AS fecha,
               p.id_paciente,
               p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS nombre_paciente,
               COALESCE(s.nombre_sede, '—') AS nombre_sede
        FROM recetas r
        JOIN pacientes p ON p.id_paciente = r.id_paciente
        LEFT JOIN sede_pacientes sp ON sp.id_paciente = p.id_paciente AND sp.fecha_salida IS NULL
        LEFT JOIN sedes s ON s.id_sede = sp.id_sede
        WHERE r.id_receta = %s
    """, (id,))
    if not receta:
        abort(404)

    medicamentos = db.query("""
        SELECT rm.id_detalle, rm.gtin, m.nombre_medicamento, rm.dosis, rm.frecuencia_horas,
               COUNT(ln.id_lectura_nfc)                                     AS total_lecturas,
               COUNT(ln.id_lectura_nfc) FILTER (WHERE ln.resultado='Exitosa') AS exitosas,
               COUNT(ln.id_lectura_nfc)
                   FILTER (WHERE ln.resultado='Exitosa'
                             AND ln.fecha_hora >= CURRENT_DATE - INTERVAL '30 days') AS exitosas_30d
        FROM receta_medicamentos rm
        JOIN medicamentos m ON m.gtin = rm.gtin
        LEFT JOIN receta_nfc rn ON rn.id_receta = rm.id_receta AND rn.fecha_fin_gestion IS NULL
        LEFT JOIN lecturas_nfc ln
            ON ln.id_receta = rm.id_receta
           AND ln.id_dispositivo = rn.id_dispositivo
        WHERE rm.id_receta = %s
        GROUP BY rm.id_detalle, rm.gtin, m.nombre_medicamento, rm.dosis, rm.frecuencia_horas
        ORDER BY m.nombre_medicamento
    """, (id,))

    medicamentos_disponibles = db.query("""
        SELECT gtin, nombre_medicamento FROM medicamentos
        WHERE gtin NOT IN (
            SELECT gtin FROM receta_medicamentos WHERE id_receta = %s
        )
        ORDER BY nombre_medicamento
    """, (id,))

    nfc = db.one("""
        SELECT rn.id_receta, rn.id_dispositivo, d.id_serial,
               TO_CHAR(rn.fecha_inicio_gestion, 'DD/MM/YYYY') AS desde,
               rn.fecha_fin_gestion
        FROM receta_nfc rn
        JOIN dispositivos d ON d.id_dispositivo = rn.id_dispositivo
        WHERE rn.id_receta = %s AND rn.fecha_fin_gestion IS NULL
    """, (id,))

    lecturas = db.query("""
        SELECT ln.id_lectura_nfc,
               TO_CHAR(ln.fecha_hora, 'DD/MM/YYYY HH24:MI') AS fecha_hora,
               ln.tipo_lectura, ln.resultado
        FROM lecturas_nfc ln
        WHERE ln.id_receta = %s
        ORDER BY ln.fecha_hora DESC
        LIMIT 20
    """, (id,))

    # NFC devices available for assignment (not currently linked to any active receta)
    nfc_disponibles = db.query("""
        SELECT d.id_dispositivo, d.id_serial, d.modelo
        FROM dispositivos d
        WHERE d.tipo = 'NFC' AND d.estado = 'Activo'
          AND d.id_dispositivo NOT IN (
              SELECT rn.id_dispositivo FROM receta_nfc rn WHERE rn.fecha_fin_gestion IS NULL
          )
        ORDER BY d.id_serial
    """)

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
        next_det = db.scalar(
            "SELECT COALESCE(MAX(id_detalle), 0) + 1 FROM receta_medicamentos"
        )
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
    # Quick live counters for the header
    stats = {
        "alertas_activas": db.scalar("SELECT COUNT(*) FROM alertas WHERE estatus='Activa'") or 0,
        "lecturas_nfc_hoy": db.scalar(
            "SELECT COUNT(*) FROM lecturas_nfc WHERE fecha_hora::date = CURRENT_DATE") or 0,
        "pacientes_activos": db.scalar(
            "SELECT COUNT(*) FROM pacientes WHERE id_estado != 3") or 0,
    }
    return render_template("reportes.html", stats=stats)


# ═══════════════════════════════════════════════════════════════════════════════
# PORTAL CLÍNICO  (médico)
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/clinica")
@medico_requerido
def clinica_sedes():
    sedes = db.query("SELECT * FROM sedes ORDER BY id_sede")
    result = []
    for s in sedes:
        total = db.scalar("""
            SELECT COUNT(*) FROM sede_pacientes
            WHERE id_sede = %s AND fecha_salida IS NULL
        """, (s["id_sede"],)) or 0
        result.append({
            "sucursal": {
                "id_sucursal": s["id_sede"],
                "nombre":      s["nombre_sede"],
                "zona":        s.get("municipio", ""),
            },
            "total_pacientes": total,
        })
    return render_template("clinica_sedes.html", sedes=result)


@app.route("/clinica/<int:id_sucursal>")
@medico_requerido
def dashboard_clinica(id_sucursal):
    sede = db.one("SELECT * FROM sedes WHERE id_sede = %s", (id_sucursal,))
    if not sede:
        return redirect(url_for("clinica_sedes"))

    sucursal = {"id_sucursal": sede["id_sede"], "nombre": sede["nombre_sede"]}

    pacientes_sede = db.query("""
        SELECT p.id_paciente,
               p.nombre           AS nombre_paciente,
               p.apellido_p       AS apellido_p_pac,
               p.apellido_m       AS apellido_m_pac,
               p.fecha_nacimiento,
               ep.desc_estado
        FROM pacientes p
        JOIN estados_paciente ep ON p.id_estado = ep.id_estado
        JOIN sede_pacientes sp   ON p.id_paciente = sp.id_paciente
        WHERE sp.id_sede = %s AND sp.fecha_salida IS NULL AND p.id_estado != 3
        ORDER BY p.nombre
    """, (id_sucursal,))

    alertas_activas_count = db.scalar("""
        SELECT COUNT(*) FROM alertas a
        JOIN sede_pacientes sp ON a.id_paciente = sp.id_paciente
        WHERE sp.id_sede = %s AND sp.fecha_salida IS NULL AND a.estatus = 'Activa'
    """, (id_sucursal,)) or 0

    from datetime import datetime as _dt
    _now = _dt.now()
    _dow = _now.weekday()  # 0=lunes … 6=domingo
    _dia_col = ["lunes","martes","miercoles","jueves","viernes","sabado","domingo"][_dow]
    staff_en_turno = db.scalar(f"""
        SELECT COUNT(DISTINCT tc.id_cuidador)
        FROM turno_cuidador tc
        JOIN sede_zonas sz ON tc.id_zona = sz.id_zona
        WHERE tc.activo = TRUE
          AND tc.hora_inicio <= CURRENT_TIME
          AND tc.hora_fin    >  CURRENT_TIME
          AND tc.{_dia_col} = TRUE
          AND sz.id_sede = %s
    """, (id_sucursal,)) or 0
    tareas_pendientes = 0  # no hay tabla tareas aún

    # Cuidadores activos por paciente para esta sede {id_paciente: [...]}
    _asig_rows = db.query("""
        SELECT ac.id_paciente,
               e.nombre     AS nombre_cuidador,
               e.apellido_p AS apellido_p_cuid,
               e.apellido_m AS apellido_m_cuid,
               e.telefono   AS telefono_cuid,
               TO_CHAR(ac.fecha_inicio, 'YYYY-MM-DD') AS fecha_asig_cuidador
        FROM asignacion_cuidador ac
        JOIN cuidadores c ON ac.id_cuidador = c.id_empleado
        JOIN empleados  e ON c.id_empleado  = e.id_empleado
        JOIN sede_pacientes sp ON ac.id_paciente = sp.id_paciente
        WHERE sp.id_sede = %s AND sp.fecha_salida IS NULL AND ac.fecha_fin IS NULL
    """, (id_sucursal,))
    asignaciones = {}
    for row in _asig_rows:
        asignaciones.setdefault(row["id_paciente"], []).append(row)

    # Medicamentos por paciente via recetas activas {id_paciente: [...]}
    _med_rows = db.query("""
        SELECT r.id_paciente,
               m.nombre_medicamento AS medicamento,
               rm.dosis,
               rm.frecuencia_horas
        FROM recetas r
        JOIN receta_medicamentos rm ON r.id_receta = rm.id_receta
        JOIN medicamentos m         ON rm.gtin     = m.gtin
        JOIN sede_pacientes sp      ON r.id_paciente = sp.id_paciente
        WHERE sp.id_sede = %s AND sp.fecha_salida IS NULL AND r.estado = 'Activa'
        ORDER BY r.id_paciente, m.nombre_medicamento
    """, (id_sucursal,))
    medicamentos_por_paciente = {}
    for row in _med_rows:
        medicamentos_por_paciente.setdefault(row["id_paciente"], []).append(row)

    ids_sede = {p["id_paciente"] for p in pacientes_sede}
    expedientes = []
    for p in pacientes_sede:
        pid = p["id_paciente"]
        enfermedades = db.query("""
            SELECT e.nombre_enfermedad,
                   TO_CHAR(te.fecha_diag, 'YYYY-MM-DD') AS fecha_diag
            FROM tiene_enfermedad te
            JOIN enfermedades e ON te.id_enfermedad = e.id_enfermedad
            WHERE te.id_paciente = %s
        """, (pid,))
        expedientes.append({
            "paciente":     p,
            "perfil":       {},  # sin tabla perfil_clinico aún
            "medicamentos": medicamentos_por_paciente.get(pid, []),
            "bitacoras":    [],  # sin tabla bitacoras clínicas aún
            "enfermedades": enfermedades,
        })

    # Incidentes = alertas reales de pacientes en esta sede
    incidentes_sede = db.query("""
        SELECT a.id_alerta                           AS id,
               TO_CHAR(a.fecha_hora, 'YYYY-MM-DD')  AS fecha,
               TO_CHAR(a.fecha_hora, 'HH24:MI')     AS hora,
               a.id_paciente,
               p.nombre || ' ' || p.apellido_p      AS paciente,
               a.tipo_alerta                         AS tipo,
               a.estatus                             AS gravedad,
               NULL                                  AS descripcion,
               NULL                                  AS accion_tomada
        FROM alertas a
        JOIN pacientes p      ON a.id_paciente = p.id_paciente
        JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
        WHERE sp.id_sede = %s AND sp.fecha_salida IS NULL
        ORDER BY a.fecha_hora DESC
        LIMIT 20
    """, (id_sucursal,))

    # Alertas médicas = alertas activas de pacientes en esta sede
    alertas_medicas = db.query("""
        SELECT a.tipo_alerta                         AS tipo,
               p.nombre || ' ' || p.apellido_p      AS paciente,
               TO_CHAR(a.fecha_hora, 'HH24:MI')     AS hora,
               TO_CHAR(a.fecha_hora, 'YYYY-MM-DD')  AS fecha,
               a.estatus                             AS estado
        FROM alertas a
        JOIN pacientes p       ON a.id_paciente = p.id_paciente
        JOIN sede_pacientes sp ON p.id_paciente  = sp.id_paciente
        WHERE sp.id_sede = %s AND sp.fecha_salida IS NULL AND a.estatus = 'Activa'
        ORDER BY a.fecha_hora DESC
        LIMIT 10
    """, (id_sucursal,))

    # Bitácora del comedor hoy en esta sede
    comedor_hoy = db.query("""
        SELECT bc.id_bitacora  AS id,
               bc.turno,
               bc.menu_nombre,
               bc.cantidad_platos,
               bc.incidencias,
               TO_CHAR(bc.fecha, 'YYYY-MM-DD') AS fecha,
               e.nombre || ' ' || e.apellido_p AS cocinero
        FROM bitacora_comedor bc
        JOIN cocineros co ON bc.id_cocinero = co.id_empleado
        JOIN empleados  e  ON co.id_empleado = e.id_empleado
        WHERE bc.id_sede = %s AND bc.fecha = CURRENT_DATE
        ORDER BY bc.turno
    """, (id_sucursal,))

    # Cobertura de zonas por turno activo ahora mismo en esta sede
    cobertura_zonas = db.query(f"""
        SELECT z.id_zona, z.nombre_zona,
               e.nombre || ' ' || e.apellido_p AS nombre_cuidador,
               tc.hora_inicio, tc.hora_fin
        FROM turno_cuidador tc
        JOIN zonas z      ON tc.id_zona     = z.id_zona
        JOIN sede_zonas sz ON z.id_zona     = sz.id_zona
        JOIN cuidadores c ON tc.id_cuidador = c.id_empleado
        JOIN empleados e  ON c.id_empleado  = e.id_empleado
        WHERE tc.activo = TRUE
          AND tc.hora_inicio <= CURRENT_TIME
          AND tc.hora_fin    >  CURRENT_TIME
          AND tc.{_dia_col}  = TRUE
          AND sz.id_sede = %s
        ORDER BY z.nombre_zona, e.nombre
    """, (id_sucursal,))

    visitas_hoy = db.query("""
        SELECT v.*, vt.nombre || ' ' || vt.apellido_p AS visitante
        FROM visitas v
        JOIN visitantes vt ON v.id_visitante = vt.id_visitante
        WHERE v.id_sede = %s AND v.fecha_entrada = CURRENT_DATE
    """, (id_sucursal,))

    entregas_pend = db.query("""
        SELECT ee.*, p.nombre || ' ' || p.apellido_p AS paciente
        FROM entregas_externas ee
        JOIN pacientes p ON ee.id_paciente = p.id_paciente
        JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
        WHERE sp.id_sede = %s AND sp.fecha_salida IS NULL AND ee.estado = 'Pendiente'
    """, (id_sucursal,))

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

        contacto = db.one("""
            SELECT id_contacto, nombre, apellido_p
            FROM contactos_emergencia
            WHERE LOWER(email) = %s AND pin_acceso = %s
        """, (email, pin))

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

    pacientes = db.query("""
        SELECT p.id_paciente,
               p.nombre        AS nombre_paciente,
               p.apellido_p    AS apellido_p_pac,
               p.apellido_m    AS apellido_m_pac,
               ep.desc_estado,
               s.nombre_sede,
               pc.prioridad
        FROM pacientes p
        JOIN paciente_contactos pc ON p.id_paciente  = pc.id_paciente
        JOIN estados_paciente   ep ON p.id_estado    = ep.id_estado
        LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                                   AND sp.fecha_salida IS NULL
        LEFT JOIN sedes s           ON sp.id_sede    = s.id_sede
        WHERE pc.id_contacto = %s AND p.id_estado != 3
        ORDER BY pc.prioridad, p.nombre
    """, (contacto_id,))

    return render_template("portal_familiar/index.html", pacientes=pacientes)


@app.route("/portal-familiar/paciente/<int:id>")
@contacto_requerido
def portal_paciente(id):
    contacto_id = session["contacto_id"]

    # ── Security: verify contact-patient link ────────────────────────────────
    if not db.one("""
        SELECT 1 FROM paciente_contactos
        WHERE id_paciente = %s AND id_contacto = %s
    """, (id, contacto_id)):
        abort(403)

    # ── Patient header ───────────────────────────────────────────────────────
    paciente = db.one("""
        SELECT p.id_paciente,
               p.nombre        AS nombre_paciente,
               p.apellido_p    AS apellido_p_pac,
               p.apellido_m    AS apellido_m_pac,
               p.fecha_nacimiento,
               ep.desc_estado,
               s.nombre_sede
        FROM pacientes p
        JOIN estados_paciente ep ON p.id_estado    = ep.id_estado
        LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                                   AND sp.fecha_salida IS NULL
        LEFT JOIN sedes s           ON sp.id_sede    = s.id_sede
        WHERE p.id_paciente = %s
    """, (id,))

    if not paciente:
        abort(404)

    hoy = date.today()
    dob = paciente["fecha_nacimiento"]
    edad = hoy.year - dob.year - ((hoy.month, hoy.day) < (dob.month, dob.day))

    # ── Active cuidadores ────────────────────────────────────────────────────
    cuidadores = db.query("""
        SELECT e.nombre || ' ' || e.apellido_p AS nombre,
               e.telefono
        FROM asignacion_cuidador ac
        JOIN cuidadores c ON ac.id_cuidador = c.id_empleado
        JOIN empleados  e ON c.id_empleado  = e.id_empleado
        WHERE ac.id_paciente = %s AND ac.fecha_fin IS NULL
    """, (id,))

    # ── Last GPS reading (PostgreSQL lecturas_gps) ───────────────────────────
    ultima_gps = db.one("""
        SELECT lg.latitud, lg.longitud, lg.nivel_bateria,
               TO_CHAR(lg.fecha_hora, 'YYYY-MM-DD') AS fecha,
               TO_CHAR(lg.fecha_hora, 'HH24:MI')    AS hora,
               lg.fecha_hora AS ts
        FROM lecturas_gps lg
        JOIN asignacion_kit ak ON lg.id_dispositivo = ak.id_dispositivo_gps
        WHERE ak.id_paciente = %s AND ak.fecha_fin IS NULL
        ORDER BY lg.fecha_hora DESC
        LIMIT 1
    """, (id,))

    # ── Safe zones for patient's current sede ────────────────────────────────
    zonas_seguras = db.query("""
        SELECT z.id_zona, z.nombre_zona,
               z.latitud_centro, z.longitud_centro, z.radio_metros
        FROM zonas z
        JOIN sede_zonas sz   ON z.id_zona    = sz.id_zona
        JOIN sede_pacientes sp ON sz.id_sede = sp.id_sede
        WHERE sp.id_paciente = %s AND sp.fecha_salida IS NULL
    """, (id,))

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

    ultima_actividad_ts = db.scalar("""
        SELECT MAX(ts) FROM (
            SELECT lg.fecha_hora AS ts
            FROM lecturas_gps lg
            JOIN asignacion_kit ak ON lg.id_dispositivo = ak.id_dispositivo_gps
            WHERE ak.id_paciente = %s AND ak.fecha_fin IS NULL
            UNION ALL
            SELECT ln.fecha_hora FROM lecturas_nfc ln
            JOIN recetas r ON ln.id_receta = r.id_receta
            WHERE r.id_paciente = %s
            UNION ALL
            SELECT a.fecha_hora FROM alertas a WHERE a.id_paciente = %s
        ) ev
    """, (id, id, id))

    alerta_critica = db.one("""
        SELECT a.tipo_alerta, a.fecha_hora
        FROM alertas a
        WHERE a.id_paciente = %s AND a.estatus = 'Activa'
          AND a.tipo_alerta IN ('Salida de Zona', 'Botón SOS')
        ORDER BY a.fecha_hora DESC LIMIT 1
    """, (id,))

    if alerta_critica:
        estado_banner = 'critica'
    elif ultima_actividad_ts is None or (now_dt - ultima_actividad_ts).total_seconds() > 7200:
        estado_banner = 'sin_datos'
    else:
        estado_banner = 'ok'

    tiempo_actividad = _t_rel(ultima_actividad_ts)
    tiempo_alerta_critica = _t_rel(alerta_critica["fecha_hora"]) if alerta_critica else None

    # ── Alerts ───────────────────────────────────────────────────────────────
    alertas_activas = db.query("""
        SELECT a.tipo_alerta,
               TO_CHAR(a.fecha_hora, 'YYYY-MM-DD') AS fecha,
               TO_CHAR(a.fecha_hora, 'HH24:MI')    AS hora
        FROM alertas a
        WHERE a.id_paciente = %s AND a.estatus = 'Activa'
        ORDER BY a.fecha_hora DESC
    """, (id,))

    alertas_historial = db.query("""
        SELECT a.tipo_alerta,
               TO_CHAR(a.fecha_hora, 'YYYY-MM-DD') AS fecha,
               TO_CHAR(a.fecha_hora, 'HH24:MI')    AS hora
        FROM alertas a
        WHERE a.id_paciente = %s
          AND a.estatus = 'Atendida'
          AND a.fecha_hora >= NOW() - INTERVAL '30 days'
        ORDER BY a.fecha_hora DESC
    """, (id,))

    # ── Medications (active recetas only, with today's NFC status) ───────────
    medicamentos = db.query("""
        SELECT m.nombre_medicamento, rm.dosis, rm.frecuencia_horas,
               EXISTS (
                   SELECT 1 FROM lecturas_nfc ln
                   WHERE ln.id_receta = r.id_receta
                     AND ln.fecha_hora::DATE = CURRENT_DATE
                     AND ln.resultado = 'Exitosa'
               ) AS tomada_hoy
        FROM recetas r
        JOIN receta_medicamentos rm ON r.id_receta = rm.id_receta
        JOIN medicamentos m         ON rm.gtin     = m.gtin
        WHERE r.id_paciente = %s AND r.estado = 'Activa'
        ORDER BY m.nombre_medicamento
    """, (id,))

    # NFC adherence today
    dosis_hoy = db.scalar("""
        SELECT COUNT(*)
        FROM lecturas_nfc ln
        WHERE ln.id_receta IN (
            SELECT id_receta FROM recetas WHERE id_paciente = %s
        )
          AND ln.fecha_hora::DATE = CURRENT_DATE
          AND ln.resultado = 'Exitosa'
    """, (id,)) or 0

    # ── Recent visits ────────────────────────────────────────────────────────
    visitas = db.query("""
        SELECT TO_CHAR(v.fecha_entrada, 'YYYY-MM-DD') AS fecha,
               v.hora_entrada, v.hora_salida,
               vt.nombre || ' ' || vt.apellido_p AS visitante,
               vt.relacion
        FROM visitas v
        JOIN visitantes vt ON v.id_visitante = vt.id_visitante
        WHERE v.id_paciente = %s
        ORDER BY v.fecha_entrada DESC, v.hora_entrada DESC
        LIMIT 10
    """, (id,))

    # ── Last caregiver round (beacon detections near patient's building) ──────
    # NOTE: will migrate to MongoDB ble_events when beacon ingest is complete
    ultima_ronda = db.scalar("""
        SELECT MAX(db2.fecha_hora)
        FROM detecciones_beacon db2
        JOIN beacon_zona bz   ON db2.id_dispositivo = bz.id_dispositivo
        JOIN sede_zonas sz    ON bz.id_zona          = sz.id_zona
        JOIN sede_pacientes sp ON sz.id_sede         = sp.id_sede
        WHERE sp.id_paciente = %s AND sp.fecha_salida IS NULL
    """, (id,))

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
    # Load zones that have an active beacon assigned so the manual-mode buttons
    # know which device ID to post.
    zonas = db.query(
        """SELECT z.id_zona, z.nombre_zona, d.id_dispositivo, d.id_serial
           FROM zonas z
           JOIN beacon_zona bz ON z.id_zona = bz.id_zona
           JOIN dispositivos d  ON bz.id_dispositivo = d.id_dispositivo
           WHERE d.estado = 'Activo'
           ORDER BY z.nombre_zona"""
    )
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
        device = db.one(
            "SELECT id_dispositivo FROM dispositivos WHERE tipo='NFC' AND LOWER(id_serial)=LOWER(%s)",
            [data["serial"]]
        )
        if not device:
            return jsonify({"status": "error", "error": f"Serial '{data['serial']}' no registrado"}), 404
        id_dispositivo = device["id_dispositivo"]

    if not id_dispositivo:
        return jsonify({"status": "error", "message": "Falta id_dispositivo o serial"}), 400

    # Resolve id_receta from active link if not provided
    if not id_receta:
        link = db.one(
            "SELECT id_receta FROM receta_nfc WHERE id_dispositivo=%s AND fecha_fin_gestion IS NULL",
            [id_dispositivo]
        )
        if not link:
            return jsonify({"status": "error", "error": "No hay receta activa vinculada a este dispositivo NFC"}), 404
        id_receta = link["id_receta"]

    try:
        next_id = db.scalar("SELECT COALESCE(MAX(id_lectura_nfc), 0) + 1 FROM lecturas_nfc")
        db.execute(
            "CALL sp_nfc_registrar_lectura(%s, %s, %s, NOW(), %s, %s)",
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

    data = request.get_json(silent=True) or {}
    id_cuidador = data.get("id_empleado")   # accepts legacy field name
    id_beacon   = data.get("id_beacon")
    serial      = data.get("serial")
    rssi        = data.get("rssi")

    # ── Resolve beacon ─────────────────────────────────────────────────────────
    # Priority: id_beacon > serial > uuid+major+minor composite key
    if not id_beacon and serial:
        row = db.one(
            "SELECT id_dispositivo FROM dispositivos WHERE tipo='BEACON' AND LOWER(id_serial)=LOWER(%s)",
            [serial]
        )
        if row:
            id_beacon = row["id_dispositivo"]

    if not id_beacon and data.get("uuid") and data.get("major") is not None and data.get("minor") is not None:
        # Build composite key from first 8 chars of UUID + Major + Minor
        uuid_prefix = str(data["uuid"]).upper()[:8]
        composite   = f"{uuid_prefix}-{data['major']}-{data['minor']}"
        row = db.one(
            "SELECT id_dispositivo FROM dispositivos WHERE tipo='BEACON' AND UPPER(id_serial)=%s",
            [composite]
        )
        if row:
            id_beacon = row["id_dispositivo"]

    # ── Resolve cuidador from session if not provided ──────────────────────────
    if not id_cuidador and session.get("medico"):
        emp = db.one(
            "SELECT c.id_empleado FROM cuidadores c JOIN empleados e ON c.id_empleado = e.id_empleado WHERE e.usuario = %s",
            [session.get("medico")]
        )
        if emp:
            id_cuidador = emp["id_empleado"]

    if not id_beacon:
        return jsonify({"status": "error", "message": "Beacon no identificado (falta id_beacon, serial, o uuid+major+minor)"}), 400

    try:
        # sp_cuidador_registrar_ronda handles ID generation, validation, and insert.
        # trg_cobertura_zona fires automatically inside the SP's INSERT.
        db.execute(
            "CALL sp_cuidador_registrar_ronda(%s, %s, %s)",
            (id_beacon, id_cuidador, rssi if rssi is not None else 0)
        )

        # Fetch the id_deteccion just inserted and the zone name for the response
        row = db.one(
            """SELECT db.id_deteccion, z.nombre_zona
               FROM detecciones_beacon db
               LEFT JOIN beacon_zona bz ON db.id_dispositivo = bz.id_dispositivo
               LEFT JOIN zonas z        ON bz.id_zona = z.id_zona
               WHERE db.id_dispositivo = %s
               ORDER BY db.fecha_hora DESC
               LIMIT 1""",
            [id_beacon]
        )
        return jsonify({
            "status": "ok",
            "ok": True,
            "id_deteccion": row["id_deteccion"] if row else None,
            "zone_name":    row["nombre_zona"]  if row else None,
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
    dispositivos_gps = db.query("""
        SELECT d.id_dispositivo, d.id_serial, d.modelo,
               p.nombre || ' ' || p.apellido_p AS paciente,
               ak.id_paciente
        FROM dispositivos d
        JOIN asignacion_kit ak ON ak.id_dispositivo_gps = d.id_dispositivo
                              AND ak.fecha_fin IS NULL
        JOIN pacientes p ON p.id_paciente = ak.id_paciente
        WHERE d.tipo = 'GPS' AND d.estado = 'Activo' AND p.id_estado != 3
        ORDER BY p.nombre
    """)

    result = None
    if request.method == "POST":
        try:
            id_dispositivo = int(request.form["id_dispositivo"])
            latitud        = float(request.form["latitud"])
            longitud       = float(request.form["longitud"])
            nivel_bateria  = int(request.form.get("nivel_bateria") or 80)

            next_id = db.scalar("SELECT COALESCE(MAX(id_lectura), 0) + 1 FROM lecturas_gps")
            db.execute("""
                INSERT INTO lecturas_gps
                    (id_lectura, id_dispositivo, fecha_hora, latitud, longitud, nivel_bateria, geom)
                VALUES (
                    %s, %s, NOW(), %s, %s, %s,
                    ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography
                )
            """, (next_id, id_dispositivo, latitud, longitud, nivel_bateria, longitud, latitud))

            # Check what alerts were generated by the triggers
            nuevas_alertas = db.query("""
                SELECT id_alerta, tipo_alerta, estatus
                FROM alertas
                ORDER BY id_alerta DESC
                LIMIT 3
            """)
            result = {
                "id_lectura": next_id,
                "latitud": latitud,
                "longitud": longitud,
                "nivel_bateria": nivel_bateria,
                "alertas_generadas": nuevas_alertas,
            }
            flash(f"Lectura GPS #{next_id} insertada. Triggers ejecutados.", "success")
        except Exception as e:
            flash(f"Error al simular lectura GPS: {e}", "error")

    zonas_ref = db.query("""
        SELECT z.id_zona, z.nombre_zona, z.latitud_centro, z.longitud_centro,
               z.radio_metros, s.nombre_sede
        FROM zonas z
        LEFT JOIN sede_zonas sz ON sz.id_zona = z.id_zona
        LEFT JOIN sedes s ON s.id_sede = sz.id_sede
        ORDER BY z.id_zona
    """)

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
        next_id = db.scalar("SELECT COALESCE(MAX(id_lectura), 0) + 1 FROM lecturas_gps")
        db.execute("""
            INSERT INTO lecturas_gps
                (id_lectura, id_dispositivo, fecha_hora, latitud, longitud, altura, nivel_bateria, geom)
            VALUES (
                %s, %s, NOW(), %s, %s, %s, %s,
                ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography
            )
        """, (next_id, id_dispositivo, latitud, longitud, altura, nivel_bateria, longitud, latitud))
        return jsonify({"status": "ok", "id_lectura": next_id})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 422


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

    # Look up by exact serial, case-insensitive
    device = db.one(
        """
        SELECT id_dispositivo, id_serial, modelo, estado
        FROM dispositivos
        WHERE tipo = 'NFC'
          AND LOWER(id_serial) = LOWER(%s)
        """,
        [tag_serial],
    )

    if not device:
        app.logger.info("Unknown NFC tag scanned: %s", tag_serial)
        return jsonify({
            "status": "not_found",
            "tag_serial": tag_serial,
            "message": "Tag not registered. Add this serial to Dispositivos as type NFC.",
        })

    # Find linked patient via asignacion_nfc (direct identity link)
    patient = db.one(
        """
        SELECT p.id_paciente, p.nombre, p.apellido_p
        FROM asignacion_nfc an
        JOIN pacientes p ON an.id_paciente = p.id_paciente
        WHERE an.id_dispositivo = %s AND an.fecha_fin IS NULL
        """,
        [device["id_dispositivo"]],
    )

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
    if not os.path.exists("cert.pem"):
        os.system(
            'openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem '
            '-days 365 -nodes -subj "/CN=localhost"'
        )
    app.run(debug=True, host="0.0.0.0", port=5002, ssl_context=("cert.pem", "key.pem"))
