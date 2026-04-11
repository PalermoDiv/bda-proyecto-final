from flask import Flask, render_template, request, redirect, url_for, session, flash
from functools import wraps
from dotenv import load_dotenv
from datetime import date
import os
import db
import data  # clinica-specific in-memory structures not yet in DB

load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "clave-secreta-dev")


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
    if request.method == "POST":
        try:
            id_pac     = int(request.form["id_paciente"])
            nombre     = request.form["nombre_paciente"].strip()
            apellido_p = request.form["apellido_p_pac"].strip()
            apellido_m = request.form["apellido_m_pac"].strip()
            fecha_nac  = request.form["fecha_nacimiento"]
            id_estado  = int(request.form["id_estado"])

            db.execute("""
                INSERT INTO pacientes
                    (id_paciente, nombre, apellido_p, apellido_m, fecha_nacimiento, id_estado)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (id_pac, nombre, apellido_p, apellido_m, fecha_nac, id_estado))

            flash("Paciente registrado correctamente.", "success")
            return redirect(url_for("pacientes_lista"))
        except Exception as e:
            flash(f"Error al registrar paciente: {e}", "error")

    return render_template("pacientes/form.html", paciente=None, estados=estados)


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

    return render_template("pacientes/form.html", paciente=paciente, estados=estados)


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
        WHERE ak.id_paciente = %s
        LIMIT 1
    """, (id,))

    ingreso = db.one("""
        SELECT TO_CHAR(sp.fecha_ingreso, 'YYYY-MM-DD') AS fecha_ingreso,
               sp.hora_ingreso,
               s.nombre_sede
        FROM sede_pacientes sp
        JOIN sedes s ON sp.id_sede = s.id_sede
        WHERE sp.id_paciente = %s AND sp.fecha_salida IS NULL
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

    return render_template(
        "pacientes/historial.html",
        paciente=paciente,
        estado=estado,
        enfermedades=enfermedades,
        cuidadores=cuidadores,
        contactos=contactos,
        kit=kit,
        ingreso=ingreso,
        visitas=visitas,
        entregas=entregas,
    )


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
# ALERTAS
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/alertas")
@admin_requerido
def alertas():
    alertas_list = db.query("""
        SELECT a.id_alerta, a.tipo_alerta, a.estatus, a.fecha_hora,
               p.nombre || ' ' || p.apellido_p || ' ' || p.apellido_m AS paciente,
               s.nombre_sede AS nombre_sucursal
        FROM alertas a
        JOIN pacientes p ON a.id_paciente = p.id_paciente
        LEFT JOIN sede_pacientes sp ON p.id_paciente = sp.id_paciente
                                   AND sp.fecha_salida IS NULL
        LEFT JOIN sedes s ON sp.id_sede = s.id_sede
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
            id_alerta   = int(request.form["id_alerta"])
            id_paciente = int(request.form["id_paciente"])
            tipo_alerta = request.form["tipo_alerta"]
            fecha_hora  = request.form["fecha_hora"]

            db.execute("""
                INSERT INTO alertas (id_alerta, id_paciente, tipo_alerta, fecha_hora, estatus)
                VALUES (%s, %s, %s, %s, 'Activa')
            """, (id_alerta, id_paciente, tipo_alerta, fecha_hora))

            flash("Alerta registrada.", "success")
            return redirect(url_for("alertas"))
        except Exception as e:
            flash(f"Error al registrar alerta: {e}", "error")

    return render_template("alertas_form.html", pacientes=pacientes, tipos=tipos,
                           fecha_hoy=date.today().isoformat())


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
               ON d.id_dispositivo = ak.id_dispositivo_gps
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
               '—' AS paciente,
               '—' AS notificar_a
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

    staff_en_turno    = sum(1 for t in data.TURNOS_HOY if t["estado"] == "En turno")
    tareas_pendientes = sum(1 for t in data.TAREAS_HOY if t["estado"] == "Pendiente")

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
            "perfil":       data.PERFIL_CLINICO.get(pid, {}),
            "medicamentos": data.MEDICAMENTOS.get(pid, []),
            "bitacoras":    [b for b in data.BITACORAS if b["id_paciente"] == pid],
            "enfermedades": enfermedades,
        })

    incidentes_sede = [i for i in data.INCIDENTES if i["id_paciente"] in ids_sede]
    comedor_hoy     = [b for b in data.BITACORA_COMEDOR if b["id_sede"] == id_sucursal]

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
        tareas=data.TAREAS_HOY,
        alertas_medicas=data.ALERTAS_MEDICAS,
        turnos=data.TURNOS_HOY,
        asignaciones=data.ASIGNACIONES_CUIDADORES,
        pacientes=pacientes_sede,
        expedientes=expedientes,
        incidentes=incidentes_sede,
        comedor_hoy=comedor_hoy,
        visitas_hoy=visitas_hoy,
        entregas_pendientes=entregas_pend,
    )


# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5002)
