from flask import Blueprint, render_template, request, redirect, url_for, flash
import models.zona as Zona
import models.sede as Sede
import db
from auth import admin_requerido

bp = Blueprint("zonas", __name__, url_prefix="/zonas")


@bp.route("/")
@admin_requerido
def zonas():
    return render_template("zonas.html", zonas=Zona.listar())


@bp.route("/nueva", methods=["GET", "POST"])
@admin_requerido
def zonas_nueva():
    sedes = Sede.listar()
    if request.method == "POST":
        try:
            id_zona     = Zona.siguiente_id()
            nombre_zona = request.form["nombre_zona"].strip()
            latitud     = float(request.form["latitud_centro"])
            longitud    = float(request.form["longitud_centro"])
            radio       = float(request.form["radio_metros"])
            sedes_sel   = request.form.getlist("id_sedes")

            statements = [
                ("CALL sp_ins_zona(%s, %s, %s, %s, %s)",
                 (id_zona, nombre_zona, latitud, longitud, radio)),
            ]
            for id_sede in sedes_sel:
                statements.append(
                    ("CALL sp_ins_sede_zona(%s, %s)", (id_zona, int(id_sede)))
                )
            db.execute_many(statements)

            flash("Zona segura registrada correctamente.", "success")
            return redirect(url_for("zonas.zonas"))
        except Exception as e:
            flash(f"Error al registrar zona: {e}", "error")
    return render_template("zonas_form.html", zona=None, sedes=sedes, sedes_asignadas=[])


@bp.route("/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def zonas_editar(id):
    zona = Zona.obtener(id)
    if not zona:
        flash("Zona no encontrada.", "error")
        return redirect(url_for("zonas.zonas"))

    sedes           = Sede.listar()
    sedes_asignadas = [r["id_sede"] for r in Zona.sedes_asignadas(id)]

    if request.method == "POST":
        try:
            nombre_zona = request.form["nombre_zona"].strip()
            latitud     = float(request.form["latitud_centro"])
            longitud    = float(request.form["longitud_centro"])
            radio       = float(request.form["radio_metros"])
            sedes_sel   = request.form.getlist("id_sedes")

            statements = [
                ("CALL sp_upd_zona(%s, %s, %s, %s, %s)",
                 (id, nombre_zona, latitud, longitud, radio)),
                ("CALL sp_del_sedes_zona(%s)", (id,)),
            ]
            for id_sede in sedes_sel:
                statements.append(
                    ("CALL sp_ins_sede_zona(%s, %s)", (id, int(id_sede)))
                )
            db.execute_many(statements)

            flash("Zona actualizada correctamente.", "success")
            return redirect(url_for("zonas.zonas"))
        except Exception as e:
            flash(f"Error al actualizar zona: {e}", "error")

    return render_template("zonas_form.html", zona=zona, sedes=sedes,
                           sedes_asignadas=sedes_asignadas)


@bp.route("/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def zonas_eliminar(id):
    try:
        Zona.eliminar(id)
        flash("Zona eliminada.", "success")
    except Exception as e:
        flash(f"Error al eliminar zona: {e}", "error")
    return redirect(url_for("zonas.zonas"))
