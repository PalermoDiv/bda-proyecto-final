from flask import Blueprint, render_template, request, redirect, url_for, flash
import db
from auth import admin_requerido

bp = Blueprint("cuidadores", __name__, url_prefix="/cuidadores")


@bp.route("/")
@admin_requerido
def cuidadores_lista():
    cuidadores = db.query_sp("sp_sel_cuidadores")
    return render_template("cuidadores/list.html",
                           cuidadores=cuidadores,
                           sucursales=db.query_sp("sp_sel_sedes"))


@bp.route("/nuevo", methods=["GET", "POST"])
@admin_requerido
def cuidadores_nuevo():
    if request.method == "POST":
        try:
            id_cuid    = db.one_sp("sp_sel_next_id_empleado")["next_id"]
            nombre     = request.form["nombre_cuidador"].strip()
            apellido_p = request.form["apellido_p_cuid"].strip()
            apellido_m = request.form["apellido_m_cuid"].strip()
            telefono   = request.form.get("telefono_cuid", "").strip() or None
            curp       = request.form["curp_pasaporte"].strip()
            db.execute("CALL sp_ins_cuidador(%s, %s, %s, %s, %s, %s)",
                       (id_cuid, nombre, apellido_p, apellido_m, curp, telefono))
            flash("Cuidador registrado correctamente.", "success")
            return redirect(url_for("cuidadores.cuidadores_lista"))
        except Exception as e:
            flash(f"Error al registrar cuidador: {e}", "error")
    return render_template("cuidadores/form.html", cuidador=None)


@bp.route("/editar/<int:id>", methods=["GET", "POST"])
@admin_requerido
def cuidadores_editar(id):
    cuidador = db.one_sp("sp_sel_cuidador_por_id", (id,))
    if not cuidador:
        flash("Cuidador no encontrado.", "error")
        return redirect(url_for("cuidadores.cuidadores_lista"))
    if request.method == "POST":
        try:
            nombre     = request.form["nombre_cuidador"].strip()
            apellido_p = request.form["apellido_p_cuid"].strip()
            apellido_m = request.form["apellido_m_cuid"].strip()
            telefono   = request.form.get("telefono_cuid", "").strip() or None
            curp       = request.form["curp_pasaporte"].strip()
            db.execute("CALL sp_upd_cuidador(%s, %s, %s, %s, %s, %s)",
                       (id, nombre, apellido_p, apellido_m, curp, telefono))
            flash("Cuidador actualizado correctamente.", "success")
            return redirect(url_for("cuidadores.cuidadores_lista"))
        except Exception as e:
            flash(f"Error al actualizar cuidador: {e}", "error")
    return render_template("cuidadores/form.html", cuidador=cuidador)


@bp.route("/eliminar/<int:id>", methods=["POST"])
@admin_requerido
def cuidadores_eliminar(id):
    try:
        db.execute("CALL sp_del_cuidador(%s)", (id,))
        flash("Cuidador dado de baja correctamente.", "success")
    except Exception as e:
        flash(f"Error al dar de baja: {e}", "error")
    return redirect(url_for("cuidadores.cuidadores_lista"))
