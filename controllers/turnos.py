from flask import Blueprint, render_template, request, redirect, url_for, flash
import models.turno as Turno
import models.cuidador as Cuidador
import models.zona as Zona
from auth import admin_requerido

bp = Blueprint("turnos", __name__, url_prefix="/turnos")

_DIAS = ("lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo")


@bp.route("/")
@admin_requerido
def turnos_lista():
    return render_template("turnos/list.html", turnos=Turno.listar())


@bp.route("/nuevo", methods=["GET", "POST"])
@admin_requerido
def turnos_nuevo():
    if request.method == "POST":
        try:
            id_cuidador = int(request.form["id_cuidador"])
            id_zona     = int(request.form["id_zona"])
            hora_inicio = request.form["hora_inicio"]
            hora_fin    = request.form["hora_fin"]
            dias = {d: d in request.form for d in _DIAS}
            Turno.crear(id_cuidador, id_zona, hora_inicio, hora_fin, dias)
            flash("Turno registrado correctamente.", "success")
            return redirect(url_for("turnos.turnos_lista"))
        except Exception as e:
            flash(f"Error al registrar turno: {e}", "error")
    return render_template("turnos/form.html", turno=None,
                           cuidadores=Cuidador.dropdown(),
                           zonas=Zona.lista_dropdown())


@bp.route("/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def turnos_editar(id):
    turno = Turno.obtener(id)
    if not turno:
        flash("Turno no encontrado.", "error")
        return redirect(url_for("turnos.turnos_lista"))
    if request.method == "POST":
        try:
            id_cuidador = int(request.form["id_cuidador"])
            id_zona     = int(request.form["id_zona"])
            hora_inicio = request.form["hora_inicio"]
            hora_fin    = request.form["hora_fin"]
            activo      = "activo" in request.form
            dias = {d: d in request.form for d in _DIAS}
            Turno.actualizar(id, id_cuidador, id_zona, hora_inicio, hora_fin, dias, activo)
            flash("Turno actualizado correctamente.", "success")
            return redirect(url_for("turnos.turnos_lista"))
        except Exception as e:
            flash(f"Error al actualizar turno: {e}", "error")
    return render_template("turnos/form.html", turno=turno,
                           cuidadores=Cuidador.dropdown(),
                           zonas=Zona.lista_dropdown())


@bp.route("/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def turnos_eliminar(id):
    try:
        Turno.eliminar(id)
        flash("Turno eliminado correctamente.", "success")
    except Exception as e:
        flash(f"Error al eliminar turno: {e}", "error")
    return redirect(url_for("turnos.turnos_lista"))
