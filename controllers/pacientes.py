from flask import Blueprint, render_template, request, redirect, url_for, flash, send_file
import models.paciente as Paciente
import models.sede as Sede
import models.visita as Visita
import models.alerta as Alerta
import db
from auth import admin_requerido

bp = Blueprint("pacientes", __name__, url_prefix="/pacientes")


@bp.route("/")
@admin_requerido
def pacientes_lista():
    pacientes = Paciente.listar_activos()
    sedes     = Sede.listar()
    return render_template("pacientes/list.html", pacientes=pacientes, sucursales=sedes)


@bp.route("/nuevo", methods=["GET", "POST"])
@admin_requerido
def pacientes_nuevo():
    estados = Paciente.estados()
    sedes   = Sede.listar()
    if request.method == "POST":
        try:
            id_pac     = int(request.form["id_paciente"])
            nombre     = request.form["nombre_paciente"].strip()
            apellido_p = request.form["apellido_p_pac"].strip()
            apellido_m = request.form["apellido_m_pac"].strip()
            fecha_nac  = request.form["fecha_nacimiento"]
            id_estado  = int(request.form["id_estado"])
            id_sede    = int(request.form["id_sede"])
            Paciente.crear(id_pac, nombre, apellido_p, apellido_m, fecha_nac, id_estado, id_sede)
            flash("Paciente registrado correctamente.", "success")
            return redirect(url_for("pacientes.pacientes_lista"))
        except Exception as e:
            flash(f"Error al registrar paciente: {e}", "error")
    return render_template("pacientes/form.html", paciente=None, estados=estados, sedes=sedes)


@bp.route("/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def pacientes_editar(id):
    estados  = Paciente.estados()
    sedes    = Sede.listar()
    paciente = Paciente.obtener(id)
    if not paciente:
        flash("Paciente no encontrado.", "error")
        return redirect(url_for("pacientes.pacientes_lista"))

    activos        = Paciente.sede_activa(id)
    sede_actual_id = activos[0]["id_sede"] if activos else None

    if request.method == "POST":
        try:
            nombre     = request.form["nombre_paciente"].strip()
            apellido_p = request.form["apellido_p_pac"].strip()
            apellido_m = request.form["apellido_m_pac"].strip()
            fecha_nac  = request.form["fecha_nacimiento"]
            id_estado  = int(request.form["id_estado"])
            id_sede    = int(request.form["id_sede"]) if request.form.get("id_sede") else None

            statements = [
                ("CALL sp_upd_paciente(%s, %s, %s, %s, %s, %s)",
                 (id, nombre, apellido_p, apellido_m, fecha_nac, id_estado)),
            ]
            if id_sede and id_sede != sede_actual_id:
                statements.append(("CALL sp_transferir_sede(%s, %s)", (id, id_sede)))

            db.execute_many(statements)
            flash("Paciente actualizado correctamente.", "success")
            return redirect(url_for("pacientes.pacientes_lista"))
        except Exception as e:
            flash(f"Error al actualizar paciente: {e}", "error")

    return render_template("pacientes/form.html", paciente=paciente, estados=estados,
                           sedes=sedes, sede_actual_id=sede_actual_id)


@bp.route("/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def pacientes_eliminar(id):
    try:
        Paciente.eliminar(id)
        flash("Paciente dado de baja correctamente.", "success")
    except Exception as e:
        flash(f"Error al dar de baja: {e}", "error")
    return redirect(url_for("pacientes.pacientes_lista"))


@bp.route("/historial/<int:id>")
@admin_requerido
def pacientes_historial(id):
    paciente = Paciente.obtener(id)
    if not paciente:
        flash("Paciente no encontrado.", "error")
        return redirect(url_for("pacientes.pacientes_lista"))

    estado           = {"desc_estado": paciente["desc_estado"]}
    enfermedades     = Paciente.enfermedades(id)
    cuidadores       = Paciente.cuidadores(id)
    contactos        = Paciente.contactos(id)
    kit              = Paciente.kit(id)
    historial_sedes  = Paciente.historial_sedes(id)
    alertas_paciente = Alerta.por_paciente(id)
    visitas          = Visita.por_paciente(id)
    entregas         = Visita.entregas_por_paciente(id)
    nfc_asignacion   = Paciente.nfc_asignacion(id)
    nfc_disponibles  = Paciente.nfc_disponibles()
    enfermedades_disponibles = Paciente.enfermedades_disponibles(id)
    gps_disponibles  = Paciente.gps_disponibles()
    lecturas_gps     = Paciente.sede_activa(id)

    from models.iot import lecturas_gps_paciente
    lecturas_gps = lecturas_gps_paciente(id, 50)

    sede_actual_id = next(
        (r["id_sede"] for r in historial_sedes if r["fecha_salida"] is None), None
    )
    sedes_disponibles = [
        s for s in Sede.listar()
        if s["id_sede"] != (sede_actual_id or 0)
    ]

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
    paciente = Paciente.obtener(id)
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
        activos = Paciente.sede_activa(id)
        if len(activos) > 1:
            raise Exception(
                f"Integridad comprometida: el paciente tiene {len(activos)} "
                "asignaciones activas simultáneas. Corrija manualmente."
            )
        if activos and activos[0]["id_sede"] == nueva_sede_id:
            flash("El paciente ya está asignado a esa sede.", "error")
            return redirect(url_for("pacientes.pacientes_historial", id=id))
        Paciente.transferir_sede(id, nueva_sede_id)
        sede_row    = Sede.obtener(nueva_sede_id)
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
        Paciente.asignar_nfc(id, id_dispositivo)
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
        Paciente.agregar_enfermedad(id, id_enfermedad, fecha_diag)
        flash("Enfermedad agregada correctamente.", "success")
    except Exception as e:
        flash(f"Error al agregar enfermedad: {e}", "error")
    return redirect(url_for("pacientes.pacientes_historial", id=id))


@bp.route("/<int:id>/quitar-enfermedad", methods=["POST"])
@admin_requerido
def pacientes_quitar_enfermedad(id):
    try:
        id_enfermedad = int(request.form["id_enfermedad"])
        Paciente.quitar_enfermedad(id, id_enfermedad)
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
        Paciente.agregar_contacto(id, nombre, apellido_p, apellido_m,
                                  telefono, relacion, email, pin_acceso)
        flash("Contacto de emergencia agregado correctamente.", "success")
    except Exception as e:
        flash(f"Error al agregar contacto: {e}", "error")
    return redirect(url_for("pacientes.pacientes_historial", id=id))


@bp.route("/<int:id>/asignar-kit", methods=["POST"])
@admin_requerido
def pacientes_asignar_kit(id):
    try:
        id_gps = int(request.form["id_dispositivo_gps"])
        Paciente.asignar_kit(id, id_gps)
        flash("Kit GPS asignado correctamente.", "success")
    except Exception as e:
        flash(f"Error al asignar kit GPS: {e}", "error")
    return redirect(url_for("pacientes.pacientes_historial", id=id))


@bp.route("/<int:id>/cambiar-kit", methods=["POST"])
@admin_requerido
def pacientes_cambiar_kit(id):
    try:
        id_gps = int(request.form["id_dispositivo_gps"])
        Paciente.cambiar_kit(id, id_gps)
        flash("Kit GPS reasignado correctamente.", "success")
    except Exception as e:
        flash(f"Error al reasignar kit GPS: {e}", "error")
    return redirect(url_for("pacientes.pacientes_historial", id=id))
