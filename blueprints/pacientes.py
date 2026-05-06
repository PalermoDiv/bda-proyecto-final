from flask import Blueprint, render_template, request, redirect, url_for, flash, send_file
import db
from auth import admin_requerido

bp = Blueprint("pacientes", __name__, url_prefix="/pacientes")


@bp.route("/")
@admin_requerido
def pacientes_lista():
    pacientes = db.query_sp("sp_sel_pacientes_activos")
    sedes     = db.query_sp("sp_sel_sedes")
    return render_template("pacientes/list.html", pacientes=pacientes, sucursales=sedes)


@bp.route("/nuevo", methods=["GET", "POST"])
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
            return redirect(url_for("pacientes.pacientes_lista"))
        except Exception as e:
            flash(f"Error al registrar paciente: {e}", "error")
    return render_template("pacientes/form.html", paciente=None, estados=estados, sedes=sedes)


@bp.route("/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def pacientes_editar(id):
    estados  = db.query_sp("sp_sel_estados_paciente")
    paciente = db.one_sp("sp_sel_paciente_por_id", (id,))
    if not paciente:
        flash("Paciente no encontrado.", "error")
        return redirect(url_for("pacientes.pacientes_lista"))
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
            return redirect(url_for("pacientes.pacientes_lista"))
        except Exception as e:
            flash(f"Error al actualizar paciente: {e}", "error")
    return render_template("pacientes/form.html", paciente=paciente, estados=estados, sedes=[])


@bp.route("/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def pacientes_eliminar(id):
    try:
        db.execute("CALL sp_del_paciente(%s)", (id,))
        flash("Paciente dado de baja correctamente.", "success")
    except Exception as e:
        flash(f"Error al dar de baja: {e}", "error")
    return redirect(url_for("pacientes.pacientes_lista"))


@bp.route("/historial/<int:id>")
@admin_requerido
def pacientes_historial(id):
    paciente = db.one_sp("sp_sel_paciente_por_id", (id,))
    if not paciente:
        flash("Paciente no encontrado.", "error")
        return redirect(url_for("pacientes.pacientes_lista"))

    estado                   = {"desc_estado": paciente["desc_estado"]}
    enfermedades             = db.query_sp("sp_sel_enfermedades_por_paciente", (id,))
    cuidadores               = db.query_sp("sp_sel_cuidadores_por_paciente", (id,))
    contactos                = db.query_sp("sp_sel_contactos_por_paciente", (id,))
    kit                      = db.one_sp("sp_sel_kit_por_paciente", (id,))
    historial_sedes          = db.query_sp("sp_sel_historial_sedes_por_paciente", (id,))
    alertas_paciente         = db.query_sp("sp_sel_alertas_por_paciente", (id,))
    visitas                  = db.query_sp("sp_sel_visitas_por_paciente", (id,))
    entregas                 = db.query_sp("sp_sel_entregas_por_paciente", (id,))
    nfc_asignacion           = db.one_sp("sp_sel_nfc_asignacion_por_paciente", (id,))
    nfc_disponibles          = db.query_sp("sp_sel_nfc_disponibles")
    enfermedades_disponibles = db.query_sp("sp_sel_enfermedades_disponibles", (id,))
    gps_disponibles          = db.query_sp("sp_sel_gps_disponibles")

    sede_actual_id = next(
        (r["id_sede"] for r in historial_sedes if r["fecha_salida"] is None), None
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


@bp.route("/<int:id>/reporte-pdf")
@admin_requerido
def pacientes_reporte_pdf(id):
    from pdf_report import generate_patient_report
    paciente = db.one_sp("sp_sel_paciente_por_id", (id,))
    if not paciente:
        flash("Paciente no encontrado.", "error")
        return redirect(url_for("pacientes.pacientes_lista"))
    buf = generate_patient_report(id)
    nombre_archivo = (
        f"reporte_{paciente['nombre_paciente'].lower()}_"
        f"{paciente['apellido_p_pac'].lower()}_{id}.pdf"
    )
    return send_file(buf, mimetype="application/pdf",
                     as_attachment=True, download_name=nombre_archivo)


@bp.route("/<int:id>/transferir-sede", methods=["POST"])
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
            return redirect(url_for("pacientes.pacientes_historial", id=id))
        db.execute("CALL sp_transferir_sede(%s, %s)", (id, nueva_sede_id))
        sede_row = db.one_sp("sp_sel_sede_por_id", (nueva_sede_id,))
        sede_nombre = sede_row["nombre_sede"] if sede_row else str(nueva_sede_id)
        flash(f"Paciente transferido a {sede_nombre} correctamente.", "success")
    except Exception as e:
        flash(f"Error al transferir paciente: {e}", "error")
    return redirect(url_for("pacientes.pacientes_historial", id=id))


@bp.route("/<int:id>/asignar-nfc", methods=["POST"])
@admin_requerido
def pacientes_asignar_nfc(id):
    try:
        id_dispositivo = int(request.form["id_dispositivo"])
        db.execute("CALL sp_nfc_asignar(%s, %s)", (id, id_dispositivo))
        flash("Pulsera NFC asignada correctamente.", "success")
    except Exception as e:
        flash(f"Error al asignar pulsera NFC: {e}", "error")
    return redirect(url_for("pacientes.pacientes_historial", id=id))


@bp.route("/<int:id>/agregar-enfermedad", methods=["POST"])
@admin_requerido
def pacientes_agregar_enfermedad(id):
    try:
        id_enfermedad = int(request.form["id_enfermedad"])
        fecha_diag    = request.form["fecha_diag"]
        db.execute("CALL sp_ins_enfermedad(%s, %s, %s)", (id, id_enfermedad, fecha_diag))
        flash("Enfermedad agregada correctamente.", "success")
    except Exception as e:
        flash(f"Error al agregar enfermedad: {e}", "error")
    return redirect(url_for("pacientes.pacientes_historial", id=id))


@bp.route("/<int:id>/quitar-enfermedad", methods=["POST"])
@admin_requerido
def pacientes_quitar_enfermedad(id):
    try:
        id_enfermedad = int(request.form["id_enfermedad"])
        db.execute("CALL sp_del_enfermedad(%s, %s)", (id, id_enfermedad))
        flash("Diagnóstico eliminado correctamente.", "success")
    except Exception as e:
        flash(f"Error al eliminar diagnóstico: {e}", "error")
    return redirect(url_for("pacientes.pacientes_historial", id=id))


@bp.route("/<int:id>/agregar-contacto", methods=["POST"])
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
    return redirect(url_for("pacientes.pacientes_historial", id=id))


@bp.route("/<int:id>/asignar-kit", methods=["POST"])
@admin_requerido
def pacientes_asignar_kit(id):
    try:
        id_gps = int(request.form["id_dispositivo_gps"])
        db.execute("CALL sp_ins_kit(%s, %s)", (id, id_gps))
        flash("Kit GPS asignado correctamente.", "success")
    except Exception as e:
        flash(f"Error al asignar kit GPS: {e}", "error")
    return redirect(url_for("pacientes.pacientes_historial", id=id))


@bp.route("/<int:id>/cambiar-kit", methods=["POST"])
@admin_requerido
def pacientes_cambiar_kit(id):
    try:
        id_gps = int(request.form["id_dispositivo_gps"])
        db.execute("CALL sp_kit_reasignar(%s, %s)", (id, id_gps))
        flash("Kit GPS reasignado correctamente.", "success")
    except Exception as e:
        flash(f"Error al reasignar kit GPS: {e}", "error")
    return redirect(url_for("pacientes.pacientes_historial", id=id))
