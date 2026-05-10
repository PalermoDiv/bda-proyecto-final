from flask import Blueprint, render_template, request, redirect, url_for, flash
from datetime import date
import models.visita as Visita
import models.paciente as Paciente
import models.sede as Sede
from auth import admin_requerido

bp = Blueprint("visitas", __name__, url_prefix="/visitas")


@bp.route("/")
@admin_requerido
def visitas():
    return render_template(
        "visitas.html",
        visitas_hoy=Visita.hoy(),
        visitas_hist=Visita.historial(),
        entregas=Visita.entregas_externas()[:30],
        fecha_hoy=date.today(),
    )


@bp.route("/nueva", methods=["GET", "POST"])
@admin_requerido
def visitas_nueva():
    if request.method == "POST":
        try:
            id_visita    = int(request.form["id_visita"])
            id_paciente  = int(request.form["id_paciente"])
            id_visitante = int(request.form["id_visitante"])
            id_sede      = int(request.form["id_sede"])
            fecha        = request.form["fecha_entrada"]
            hora         = request.form["hora_entrada"]
            Visita.crear(id_visita, id_paciente, id_visitante, id_sede, fecha, hora)
            flash("Visita registrada correctamente.", "success")
            return redirect(url_for("visitas.visitas"))
        except Exception as e:
            flash(f"Error al registrar visita: {e}", "error")

    return render_template(
        "visitas_form.html",
        pacientes=Paciente.listar_activos(),
        visitantes=Visita.visitantes(),
        sedes=Sede.listar(),
        fecha_hoy=date.today().isoformat(),
    )
