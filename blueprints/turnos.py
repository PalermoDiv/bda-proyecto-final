from flask import Blueprint, render_template, request, redirect, url_for, flash
import db
from auth import admin_requerido

bp = Blueprint("turnos", __name__, url_prefix="/turnos")

_DIAS = ("lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo")


@bp.route("/")
@admin_requerido
def turnos_lista():
    turnos = db.query_sp("sp_sel_turnos")
    return render_template("turnos/list.html", turnos=turnos)


@bp.route("/nuevo", methods=["GET", "POST"])
@admin_requerido
def turnos_nuevo():
    if request.method == "POST":
        try:
            id_turno    = int(request.form["id_turno"])
            id_cuidador = int(request.form["id_cuidador"])
            id_zona     = int(request.form["id_zona"])
            hora_inicio = request.form["hora_inicio"]
            hora_fin    = request.form["hora_fin"]
            dias = {d: d in request.form for d in _DIAS}
            db.execute(
                "CALL sp_ins_turno(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (id_turno, id_cuidador, id_zona, hora_inicio, hora_fin,
                 dias["lunes"], dias["martes"], dias["miercoles"], dias["jueves"],
                 dias["viernes"], dias["sabado"], dias["domingo"]),
            )
            flash("Turno registrado correctamente.", "success")
            return redirect(url_for("turnos.turnos_lista"))
        except Exception as e:
            flash(f"Error al registrar turno: {e}", "error")
    cuidadores = db.query_sp("sp_sel_cuidadores_dropdown")
    zonas_list = db.query_sp("sp_sel_zonas_lista")
    return render_template("turnos/form.html", turno=None,
                           cuidadores=cuidadores, zonas=zonas_list)


@bp.route("/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def turnos_editar(id):
    turno = db.one_sp("sp_sel_turno_por_id", (id,))
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
            db.execute(
                "CALL sp_upd_turno(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (id, id_cuidador, id_zona, hora_inicio, hora_fin,
                 dias["lunes"], dias["martes"], dias["miercoles"], dias["jueves"],
                 dias["viernes"], dias["sabado"], dias["domingo"], activo),
            )
            flash("Turno actualizado correctamente.", "success")
            return redirect(url_for("turnos.turnos_lista"))
        except Exception as e:
            flash(f"Error al actualizar turno: {e}", "error")
    cuidadores = db.query_sp("sp_sel_cuidadores_dropdown")
    zonas_list = db.query_sp("sp_sel_zonas_lista")
    return render_template("turnos/form.html", turno=turno,
                           cuidadores=cuidadores, zonas=zonas_list)


@bp.route("/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def turnos_eliminar(id):
    try:
        db.execute("CALL sp_del_turno(%s)", (id,))
        flash("Turno eliminado correctamente.", "success")
    except Exception as e:
        flash(f"Error al eliminar turno: {e}", "error")
    return redirect(url_for("turnos.turnos_lista"))
