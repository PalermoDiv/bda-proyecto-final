from flask import Flask, session
from dotenv import load_dotenv
from datetime import datetime
import os
import db

load_dotenv()


def create_app():
    app = Flask(__name__)
    app.secret_key = os.getenv("SECRET_KEY", "clave-secreta-dev")

    # ── Context processor: alert banner ───────────────────────────────────────
    @app.context_processor
    def inject_alertas_criticas():
        criticas = []
        if session.get("admin") or session.get("medico"):
            try:
                rows = db.query_sp("sp_sel_alertas_banner")
                now  = datetime.now()
                for r in rows:
                    delta = now - r["fecha_hora"]
                    mins  = int(delta.total_seconds() / 60)
                    if mins < 1:
                        tiempo = "hace un momento"
                    elif mins < 60:
                        tiempo = f"hace {mins} minuto{'s' if mins != 1 else ''}"
                    else:
                        hrs    = mins // 60
                        tiempo = f"hace {hrs} hora{'s' if hrs != 1 else ''}"
                    criticas.append({**dict(r), "tiempo": tiempo})
            except Exception:
                pass
        return dict(alertas_criticas=criticas)

    # ── Register blueprints ────────────────────────────────────────────────────
    from blueprints.auth          import bp as auth_bp
    from blueprints.admin         import bp as admin_bp
    from blueprints.pacientes     import bp as pacientes_bp
    from blueprints.cuidadores    import bp as cuidadores_bp
    from blueprints.turnos        import bp as turnos_bp
    from blueprints.equipamiento  import bp as equipamiento_bp
    from blueprints.alertas       import bp as alertas_bp
    from blueprints.dispositivos  import bp as dispositivos_bp
    from blueprints.zonas         import bp as zonas_bp
    from blueprints.farmacia      import bp as farmacia_bp
    from blueprints.visitas       import bp as visitas_bp
    from blueprints.recetas       import bp as recetas_bp
    from blueprints.clinica       import bp as clinica_bp
    from blueprints.portal_familiar import bp as portal_familiar_bp
    from blueprints.cuidador      import bp as cuidador_bp
    from blueprints.api           import bp as api_bp
    from blueprints.sedes         import bp as sedes_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(pacientes_bp)
    app.register_blueprint(cuidadores_bp)
    app.register_blueprint(turnos_bp)
    app.register_blueprint(equipamiento_bp)
    app.register_blueprint(alertas_bp)
    app.register_blueprint(dispositivos_bp)
    app.register_blueprint(zonas_bp)
    app.register_blueprint(farmacia_bp)
    app.register_blueprint(visitas_bp)
    app.register_blueprint(recetas_bp)
    app.register_blueprint(clinica_bp)
    app.register_blueprint(portal_familiar_bp)
    app.register_blueprint(cuidador_bp)
    app.register_blueprint(api_bp)
    app.register_blueprint(sedes_bp)

    return app


app = create_app()

if __name__ == "__main__":
    import threading
    from werkzeug.serving import make_server

    http_srv = make_server("0.0.0.0", 5003, app)
    threading.Thread(target=http_srv.serve_forever, daemon=True).start()
    print("  * Traccar/OsmAnd HTTP listener on http://0.0.0.0:5003")

    app.run(debug=False, host="0.0.0.0", port=5002,
            ssl_context=("cert.pem", "key.pem"))
