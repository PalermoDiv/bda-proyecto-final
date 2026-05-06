from flask import Blueprint, render_template
from auth import medico_requerido

bp = Blueprint("cuidador", __name__, url_prefix="/cuidador")


@bp.route("/escanear")
@medico_requerido
def cuidador_escanear():
    return render_template("cuidador/escanear.html")


@bp.route("/ronda")
def cuidador_ronda():
    return render_template("cuidador/ronda.html", zonas=[])
