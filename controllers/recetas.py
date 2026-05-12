from flask import Blueprint, render_template, request, redirect, url_for, flash, abort
from datetime import date, timedelta
import models.receta as Receta
import models.paciente as Paciente
from auth import admin_requerido

bp = Blueprint("recetas", __name__, url_prefix="/recetas")


@bp.route("/")
@admin_requerido
def recetas_lista():
    adherencia_chart = Receta.adherencia_chart()

    raw_nfc = Receta.nfc_por_dia(14)

    nfc_exito_map = {}
    total_exitosas = total_fallidas = 0
    for r in raw_nfc:
        if r["resultado"] == "Exitosa":
            total_exitosas += r["total"]
        else:
            total_fallidas += r["total"]
    nfc_exito = []
    if total_exitosas:
        nfc_exito.append({"resultado": "Exitosa", "total": total_exitosas})
    if total_fallidas:
        nfc_exito.append({"resultado": "Fallida", "total": total_fallidas})

    hoy = date.today()
    dias_labels = [(hoy - timedelta(days=i)).strftime("%d/%m") for i in range(13, -1, -1)]
    dia_map = {}
    for r in raw_nfc:
        dia_map.setdefault(r["dia"], {})[r["resultado"]] = r["total"]
    nfc_dias_labels = dias_labels
    nfc_exitosas    = [dia_map.get(d, {}).get("Exitosa", 0) for d in dias_labels]
    nfc_fallidas    = [dia_map.get(d, {}).get("Fallida", 0) for d in dias_labels]

    return render_template(
        "recetas.html",
        recetas=Receta.listar(),
        adherencia_chart=adherencia_chart,
        nfc_exito=nfc_exito,
        nfc_dias_labels=nfc_dias_labels,
        nfc_exitosas=nfc_exitosas,
        nfc_fallidas=nfc_fallidas,
    )


@bp.route("/nueva", methods=["GET", "POST"])
@admin_requerido
def recetas_nueva():
    if request.method == "POST":
        try:
            id_paciente = int(request.form["id_paciente"])
            fecha       = request.form["fecha"]
            next_id     = Receta.siguiente_id()
            Receta.crear(next_id, id_paciente, fecha)
            flash("Receta creada correctamente.", "success")
            return redirect(url_for("recetas.recetas_detalle", id=next_id))
        except Exception as e:
            flash(f"Error al crear receta: {e}", "error")
    return render_template("recetas_form.html",
                           pacientes=Paciente.listar_activos(),
                           today=date.today().isoformat())


@bp.route("/<int:id>")
@admin_requerido
def recetas_detalle(id):
    receta = Receta.obtener(id)
    if not receta:
        abort(404)
    return render_template("recetas_detalle.html",
                           receta=receta,
                           medicamentos=Receta.medicamentos(id),
                           medicamentos_disponibles=Receta.medicamentos_disponibles(id),
                           nfc=Receta.nfc_activo(id),
                           nfc_disponibles=Paciente.nfc_disponibles(),
                           lecturas=Receta.lecturas_nfc(id))


@bp.route("/<int:id>/agregar-medicamento", methods=["POST"])
@admin_requerido
def recetas_agregar_medicamento(id):
    try:
        gtin             = request.form["gtin"]
        dosis            = request.form["dosis"].strip()
        frecuencia_horas = int(request.form["frecuencia_horas"])
        next_det = Receta.siguiente_id_detalle()
        Receta.agregar_medicamento(next_det, id, gtin, dosis, frecuencia_horas)
        flash("Medicamento agregado correctamente.", "success")
    except Exception as e:
        flash(f"Error al agregar medicamento: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/actualizar-medicamento", methods=["POST"])
@admin_requerido
def recetas_actualizar_medicamento(id):
    try:
        id_detalle       = int(request.form["id_detalle"])
        dosis            = request.form["dosis"].strip()
        frecuencia_horas = int(request.form["frecuencia_horas"])
        Receta.actualizar_medicamento(id_detalle, id, dosis, frecuencia_horas)
        flash("Medicamento actualizado correctamente.", "success")
    except Exception as e:
        flash(f"Error al actualizar medicamento: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/quitar-medicamento", methods=["POST"])
@admin_requerido
def recetas_quitar_medicamento(id):
    try:
        id_detalle = int(request.form["id_detalle"])
        Receta.quitar_medicamento(id_detalle, id)
        flash("Medicamento eliminado de la receta.", "success")
    except Exception as e:
        flash(f"Error al quitar medicamento: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/cerrar", methods=["POST"])
@admin_requerido
def recetas_cerrar(id):
    try:
        Receta.cerrar(id)
        flash("Receta cerrada correctamente.", "success")
    except Exception as e:
        flash(f"Error al cerrar receta: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/activar-nfc", methods=["POST"])
@admin_requerido
def recetas_activar_nfc(id):
    try:
        id_dispositivo = int(request.form["id_dispositivo"])
        Receta.activar_nfc(id, id_dispositivo)
        flash("Pulsera NFC vinculada correctamente.", "success")
    except Exception as e:
        flash(f"Error al activar NFC: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/cerrar-nfc", methods=["POST"])
@admin_requerido
def recetas_cerrar_nfc(id):
    try:
        id_dispositivo = int(request.form["id_dispositivo"])
        Receta.cerrar_nfc(id, id_dispositivo)
        flash("Vínculo NFC cerrado.", "success")
    except Exception as e:
        flash(f"Error al cerrar NFC: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))


@bp.route("/<int:id>/cambiar-nfc", methods=["POST"])
@admin_requerido
def recetas_cambiar_nfc(id):
    try:
        id_dispositivo_nuevo = int(request.form["id_dispositivo_nuevo"])
        Receta.cambiar_nfc(id, id_dispositivo_nuevo)
        flash("Pulsera NFC reemplazada correctamente.", "success")
    except Exception as e:
        flash(f"Error al cambiar NFC: {e}", "error")
    return redirect(url_for("recetas.recetas_detalle", id=id))
