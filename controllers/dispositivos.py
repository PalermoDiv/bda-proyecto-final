from flask import Blueprint, render_template, request, redirect, url_for, flash
import models.dispositivo as Dispositivo
from auth import admin_requerido

bp = Blueprint("dispositivos", __name__, url_prefix="/dispositivos")


@bp.route("/")
@admin_requerido
def dispositivos():
    return render_template("dispositivos.html", dispositivos=Dispositivo.listar())


@bp.route("/nuevo", methods=["GET", "POST"])
@admin_requerido
def dispositivos_nuevo():
    if request.method == "POST":
        try:
            id_disp   = int(request.form["id_dispositivo"])
            id_serial = request.form["id_serial"].strip()
            tipo      = request.form["tipo"].strip()
            modelo    = request.form["modelo"].strip()
            Dispositivo.crear(id_disp, id_serial, tipo, modelo)
            flash("Dispositivo registrado correctamente.", "success")
            return redirect(url_for("dispositivos.dispositivos"))
        except Exception as e:
            flash(f"Error al registrar dispositivo: {e}", "error")
    return render_template("dispositivos_form.html")


@bp.route("/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def dispositivos_editar(id):
    disp = Dispositivo.obtener(id)
    if not disp:
        flash("Dispositivo no encontrado.", "error")
        return redirect(url_for("dispositivos.dispositivos"))
    if request.method == "POST":
        try:
            id_serial = request.form["id_serial"].strip()
            tipo      = request.form["tipo"].strip()
            modelo    = request.form["modelo"].strip()
            estado    = request.form["estado"].strip()
            Dispositivo.actualizar(id, id_serial, tipo, modelo, estado)
            flash("Dispositivo actualizado correctamente.", "success")
            return redirect(url_for("dispositivos.dispositivos"))
        except Exception as e:
            flash(f"Error al actualizar dispositivo: {e}", "error")
    return render_template("dispositivos_form.html", disp=disp)


@bp.route("/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def dispositivos_eliminar(id):
    try:
        Dispositivo.eliminar(id)
        flash("Dispositivo eliminado.", "success")
    except Exception as e:
        flash(f"Error al eliminar dispositivo: {e}", "error")
    return redirect(url_for("dispositivos.dispositivos"))
