from flask import Blueprint, render_template, request, redirect, url_for, flash
import models.sede as Sede
from auth import admin_requerido

bp = Blueprint("sedes", __name__, url_prefix="/sedes")


@bp.route("/")
@admin_requerido
def sedes_lista():
    return render_template("sedes/list.html", sedes=Sede.listar())


@bp.route("/nueva", methods=["GET", "POST"])
@admin_requerido
def sedes_nueva():
    if request.method == "POST":
        try:
            id_sede   = Sede.siguiente_id()
            nombre    = request.form["nombre_sede"].strip()
            calle     = request.form["calle"].strip()
            numero    = request.form["numero"].strip()
            municipio = request.form["municipio"].strip()
            estado    = request.form["estado"].strip()
            Sede.crear(id_sede, nombre, calle, numero, municipio, estado)
            flash("Sede registrada correctamente.", "success")
            return redirect(url_for("sedes.sedes_lista"))
        except Exception as e:
            flash(f"Error al registrar sede: {e}", "error")
    return render_template("sedes/form.html", sede=None)


@bp.route("/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def sedes_editar(id):
    sede = Sede.obtener(id)
    if not sede:
        flash("Sede no encontrada.", "error")
        return redirect(url_for("sedes.sedes_lista"))
    if request.method == "POST":
        try:
            nombre    = request.form["nombre_sede"].strip()
            calle     = request.form["calle"].strip()
            numero    = request.form["numero"].strip()
            municipio = request.form["municipio"].strip()
            estado    = request.form["estado"].strip()
            Sede.actualizar(id, nombre, calle, numero, municipio, estado)
            flash("Sede actualizada correctamente.", "success")
            return redirect(url_for("sedes.sedes_lista"))
        except Exception as e:
            flash(f"Error al actualizar sede: {e}", "error")
    return render_template("sedes/form.html", sede=sede)


@bp.route("/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def sedes_eliminar(id):
    try:
        Sede.eliminar(id)
        flash("Sede eliminada.", "success")
    except Exception as e:
        flash(f"Error al eliminar sede: {e}", "error")
    return redirect(url_for("sedes.sedes_lista"))
