from flask import Blueprint, render_template, request, redirect, url_for, flash
import db
from auth import admin_requerido

bp = Blueprint("zonas", __name__, url_prefix="/zonas")


@bp.route("/")
@admin_requerido
def zonas():
    zonas_list = db.query_sp("sp_sel_zonas")
    return render_template("zonas.html", zonas=zonas_list)


@bp.route("/nueva", methods=["GET", "POST"])
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
            return redirect(url_for("zonas.zonas"))
        except Exception as e:
            flash(f"Error al registrar zona: {e}", "error")
    sedes = db.query_sp("sp_sel_sedes")
    return render_template("zonas_form.html", zona=None, sedes=sedes)


@bp.route("/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def zonas_editar(id):
    zona = db.one_sp("sp_sel_zona_por_id", (id,))
    if not zona:
        flash("Zona no encontrada.", "error")
        return redirect(url_for("zonas.zonas"))
    if request.method == "POST":
        try:
            nombre_zona = request.form["nombre_zona"].strip()
            latitud     = float(request.form["latitud_centro"])
            longitud    = float(request.form["longitud_centro"])
            radio       = float(request.form["radio_metros"])
            db.execute("CALL sp_upd_zona(%s, %s, %s, %s, %s)",
                       (id, nombre_zona, latitud, longitud, radio))
            flash("Zona actualizada correctamente.", "success")
            return redirect(url_for("zonas.zonas"))
        except Exception as e:
            flash(f"Error al actualizar zona: {e}", "error")
    sedes = db.query_sp("sp_sel_sedes")
    return render_template("zonas_form.html", zona=zona, sedes=sedes)


@bp.route("/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def zonas_eliminar(id):
    try:
        db.execute("CALL sp_del_zona(%s)", (id,))
        flash("Zona eliminada.", "success")
    except Exception as e:
        flash(f"Error al eliminar zona: {e}", "error")
    return redirect(url_for("zonas.zonas"))
