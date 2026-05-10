from flask import Blueprint, render_template, request, redirect, url_for, flash
from datetime import date
import models.farmacia as Farmacia
import models.sede as Sede
from auth import admin_requerido

bp = Blueprint("farmacia", __name__, url_prefix="/farmacia")


@bp.route("/")
@admin_requerido
def farmacia():
    inventario   = Farmacia.inventario()
    criticos     = [row for row in inventario if row["stock_actual"] < row["stock_minimo"]]
    return render_template(
        "farmacia.html",
        inventario=inventario,
        suministros=Farmacia.suministros(),
        farmacias=Farmacia.farmacias_proveedoras(),
        criticos=criticos,
        medicamentos=Farmacia.medicamentos_catalogo(),
        sedes=Sede.listar(),
    )


@bp.route("/inventario/ajustar", methods=["POST"])
@admin_requerido
def farmacia_ajustar_stock():
    try:
        gtin        = request.form["GTIN"].strip()
        id_sede     = int(request.form["id_sede"])
        stock_nuevo = int(request.form["stock_actual"])
        Farmacia.ajustar_stock(gtin, id_sede, stock_nuevo)
        flash("Stock actualizado correctamente.", "success")
    except Exception as e:
        flash(f"Error al ajustar stock: {e}", "error")
    return redirect(url_for("farmacia.farmacia"))


@bp.route("/suministro/nuevo", methods=["GET", "POST"])
@admin_requerido
def farmacia_suministro_nuevo():
    if request.method == "POST":
        try:
            id_sum      = Farmacia.siguiente_id_suministro()
            id_farmacia = int(request.form["id_farmacia"])
            id_sede     = int(request.form["id_sede"])
            fecha       = request.form["fecha_entrega"]
            estado      = request.form.get("estado", "Pendiente")
            gtins       = request.form.getlist("GTIN[]")
            cantidades  = request.form.getlist("cantidad[]")

            if not any(g.strip() for g in gtins):
                flash("Debe agregar al menos un medicamento a la orden.", "error")
                raise ValueError("sin_lineas")

            Farmacia.crear_suministro(id_sum, id_farmacia, id_sede, fecha, estado)

            for gtin, cant in zip(gtins, cantidades):
                if not gtin.strip():
                    continue
                Farmacia.agregar_linea(id_sum, gtin.strip(), int(cant))

            flash("Orden de suministro registrada.", "success")
            return redirect(url_for("farmacia.farmacia_suministro_detalle", id=id_sum))
        except ValueError:
            pass
        except Exception as e:
            flash(f"Error al registrar suministro: {e}", "error")

    return render_template(
        "farmacia_suministro_form.html",
        farmacias=Farmacia.farmacias_proveedoras(),
        sedes=Sede.listar(),
        medicamentos=Farmacia.medicamentos_catalogo(),
        fecha_hoy=date.today().isoformat(),
    )


@bp.route("/suministro/<int:id>")
@admin_requerido
def farmacia_suministro_detalle(id):
    suministro = Farmacia.suministro_por_id(id)
    if not suministro:
        flash("Orden no encontrada.", "error")
        return redirect(url_for("farmacia.farmacia"))
    return render_template(
        "farmacia_suministro_detalle.html",
        suministro=suministro,
        lineas=Farmacia.lineas_suministro(id),
        estados=Farmacia.estados_suministro(),
        medicamentos=Farmacia.medicamentos_catalogo(),
    )


@bp.route("/suministro/<int:id>/estado", methods=["POST"])
@admin_requerido
def farmacia_suministro_estado(id):
    try:
        Farmacia.actualizar_estado_suministro(id, request.form["estado"])
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
        Farmacia.agregar_linea(id, gtin, cantidad)
        flash("Medicamento agregado a la orden.", "success")
    except Exception as e:
        flash(f"Error: {e}", "error")
    return redirect(url_for("farmacia.farmacia_suministro_detalle", id=id))


@bp.route("/suministro/<int:id>/eliminar", methods=["POST"])
@admin_requerido
def farmacia_suministro_eliminar(id):
    try:
        Farmacia.eliminar_suministro(id)
        flash("Orden eliminada.", "success")
    except Exception as e:
        flash(f"Error al eliminar: {e}", "error")
    return redirect(url_for("farmacia.farmacia"))
