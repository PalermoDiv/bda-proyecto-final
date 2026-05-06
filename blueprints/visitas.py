from flask import Blueprint, render_template, request, redirect, url_for, flash
from datetime import date
import db
from auth import admin_requerido

bp = Blueprint("visitas", __name__, url_prefix="/visitas")


@bp.route("/")
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


@bp.route("/nueva", methods=["GET", "POST"])
@admin_requerido
def visitas_nueva():
    pacientes  = db.query_sp("sp_sel_pacientes_activos")
    visitantes = db.query_sp("sp_sel_visitantes")
    sedes      = db.query_sp("sp_sel_sedes")

    if request.method == "POST":
        try:
            id_visita    = int(request.form["id_visita"])
            id_paciente  = int(request.form["id_paciente"])
            id_visitante = int(request.form["id_visitante"])
            id_sede      = int(request.form["id_sede"])
            fecha        = request.form["fecha_entrada"]
            hora         = request.form["hora_entrada"]
            db.execute("CALL sp_ins_visita(%s, %s, %s, %s, %s, %s)",
                       (id_visita, id_paciente, id_visitante, id_sede, fecha, hora))
            flash("Visita registrada correctamente.", "success")
            return redirect(url_for("visitas.visitas"))
        except Exception as e:
            flash(f"Error al registrar visita: {e}", "error")

    return render_template(
        "visitas_form.html",
        pacientes=pacientes,
        visitantes=visitantes,
        sedes=sedes,
        fecha_hoy=date.today().isoformat(),
    )
