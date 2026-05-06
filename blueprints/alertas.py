from flask import Blueprint, render_template, request, redirect, url_for, flash
from datetime import date
import db
from auth import admin_requerido

bp = Blueprint("alertas", __name__)


@bp.route("/alertas")
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


@bp.route("/alertas/nueva", methods=["GET", "POST"])
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
            db.execute("CALL sp_ins_alerta(%s, %s, %s)", (id_paciente, tipo_alerta, fecha_hora))
            flash("Alerta registrada.", "success")
            return redirect(url_for("alertas.alertas"))
        except Exception as e:
            flash(f"Error al registrar alerta: {e}", "error")

    from datetime import datetime
    now_str = date.today().isoformat() + "T" + datetime.now().strftime("%H:%M")
    return render_template("alertas_form.html", pacientes=pacientes, tipos=tipos,
                           fecha_hoy=date.today().isoformat(), now=now_str)


@bp.route("/alertas/resolver/<int:id>", methods=["POST"])
@admin_requerido
def alertas_resolver(id):
    try:
        db.execute("CALL sp_upd_alerta_atendida(%s)", (id,))
        flash("Alerta marcada como atendida.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("alertas.alertas"))


@bp.route("/alertas/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def alertas_eliminar(id):
    try:
        db.execute("CALL sp_del_alerta(%s)", (id,))
        flash("Alerta eliminada.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("alertas.alertas"))
