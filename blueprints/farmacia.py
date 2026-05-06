from flask import Blueprint, render_template, request, redirect, url_for, flash
from datetime import date
import db
from auth import admin_requerido

bp = Blueprint("farmacia", __name__, url_prefix="/farmacia")


@bp.route("/")
@admin_requerido
def farmacia():
    inventario   = db.query_sp("sp_sel_inventario_farmacia")
    criticos     = [row for row in inventario if row["stock_actual"] < row["stock_minimo"]]
    suministros  = db.query_sp("sp_sel_suministros")
    farmacias    = db.query_sp("sp_sel_farmacias_proveedoras")
    medicamentos = db.query_sp("sp_sel_medicamentos_catalogo")
    sedes        = db.query_sp("sp_sel_sedes")
    return render_template(
        "farmacia.html",
        inventario=inventario,
        suministros=suministros,
        farmacias=farmacias,
        criticos=criticos,
        medicamentos=medicamentos,
        sedes=sedes,
    )


@bp.route("/inventario/ajustar", methods=["POST"])
@admin_requerido
def farmacia_ajustar_stock():
    try:
        gtin        = request.form["GTIN"].strip()
        id_sede     = int(request.form["id_sede"])
        stock_nuevo = int(request.form["stock_actual"])
        db.execute("CALL sp_upd_stock(%s, %s, %s)", (gtin, id_sede, stock_nuevo))
        flash("Stock actualizado correctamente.", "success")
    except Exception as e:
        flash(f"Error al ajustar stock: {e}", "error")
    return redirect(url_for("farmacia.farmacia"))


@bp.route("/suministro/nuevo", methods=["GET", "POST"])
@admin_requerido
def farmacia_suministro_nuevo():
    farmacias    = db.query_sp("sp_sel_farmacias_proveedoras")
    sedes        = db.query_sp("sp_sel_sedes")
    medicamentos = db.query_sp("sp_sel_medicamentos_catalogo")

    if request.method == "POST":
        try:
            id_sum      = db.one_sp("sp_sel_next_id_suministro")["next_id"]
            id_farmacia = int(request.form["id_farmacia"])
            id_sede     = int(request.form["id_sede"])
            fecha       = request.form["fecha_entrega"]
            estado      = request.form.get("estado", "Pendiente")
            gtins       = request.form.getlist("GTIN[]")
            cantidades  = request.form.getlist("cantidad[]")

            if not any(g.strip() for g in gtins):
                flash("Debe agregar al menos un medicamento a la orden.", "error")
                raise ValueError("sin_lineas")

            db.execute("CALL sp_ins_suministro(%s, %s, %s, %s, %s)",
                       (id_sum, id_farmacia, id_sede, fecha, estado))

            for gtin, cant in zip(gtins, cantidades):
                if not gtin.strip():
                    continue
                db.execute("CALL sp_ins_suministro_linea(%s, %s, %s)",
                           (id_sum, gtin.strip(), int(cant)))

            flash("Orden de suministro registrada.", "success")
            return redirect(url_for("farmacia.farmacia_suministro_detalle", id=id_sum))
        except ValueError:
            pass
        except Exception as e:
            flash(f"Error al registrar suministro: {e}", "error")

    return render_template(
        "farmacia_suministro_form.html",
        farmacias=farmacias,
        sedes=sedes,
        medicamentos=medicamentos,
        fecha_hoy=date.today().isoformat(),
    )


@bp.route("/suministro/<int:id>")
@admin_requerido
def farmacia_suministro_detalle(id):
    suministro = db.one_sp("sp_sel_suministro_por_id", (id,))
    if not suministro:
        flash("Orden no encontrada.", "error")
        return redirect(url_for("farmacia.farmacia"))
    lineas       = db.query_sp("sp_sel_lineas_suministro_por_id", (id,))
    estados      = db.query_sp("sp_sel_cat_estado_suministro")
    medicamentos = db.query_sp("sp_sel_medicamentos_catalogo")
    return render_template(
        "farmacia_suministro_detalle.html",
        suministro=suministro,
        lineas=lineas,
        estados=estados,
        medicamentos=medicamentos,
    )


@bp.route("/suministro/<int:id>/estado", methods=["POST"])
@admin_requerido
def farmacia_suministro_estado(id):
    try:
        nuevo_estado = request.form["estado"]
        db.execute("CALL sp_upd_suministro_estado(%s, %s)", (id, nuevo_estado))
        flash("Estado de la orden actualizado.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("farmacia.farmacia_suministro_detalle", id=id))


@bp.route("/suministro/<int:id>/linea/agregar", methods=["POST"])
@admin_requerido
def farmacia_suministro_agregar_linea(id):
    try:
        gtin     = request.form["GTIN"].strip()
        cantidad = int(request.form["cantidad"])
        db.execute("CALL sp_ins_suministro_linea(%s, %s, %s)", (id, gtin, cantidad))
        flash("Medicamento agregado a la orden.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("farmacia.farmacia_suministro_detalle", id=id))


@bp.route("/suministro/<int:id>/eliminar", methods=["POST"])
@admin_requerido
def farmacia_suministro_eliminar(id):
    try:
        db.execute("CALL sp_del_suministro(%s)", (id,))
        flash("Orden eliminada.", "success")
    except Exception as e:
        flash(f"Error al eliminar: {e}", "error")
    return redirect(url_for("farmacia.farmacia"))
