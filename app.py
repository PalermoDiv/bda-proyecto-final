from flask import Flask, session
from dotenv import load_dotenv
from datetime import datetime
import os
import models.alerta as Alerta

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
                rows = Alerta.banner()
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
        return dict(alertas_criticas=criticas, now=datetime.now())

    # ── Register controllers ───────────────────────────────────────────────────
    from controllers.auth          import bp as auth_bp
    from controllers.admin         import bp as admin_bp
    from controllers.pacientes     import bp as pacientes_bp
    from controllers.cuidadores    import bp as cuidadores_bp
    from controllers.turnos        import bp as turnos_bp
    from controllers.equipamiento  import bp as equipamiento_bp
    from controllers.alertas       import bp as alertas_bp
    from controllers.dispositivos  import bp as dispositivos_bp
    from controllers.zonas         import bp as zonas_bp
    from controllers.farmacia      import bp as farmacia_bp
    from controllers.visitas       import bp as visitas_bp
    from controllers.recetas       import bp as recetas_bp
    from controllers.clinica       import bp as clinica_bp
    from controllers.portal_familiar import bp as portal_familiar_bp
    from controllers.cuidador      import bp as cuidador_bp
    from controllers.api           import bp as api_bp
    from controllers.sedes         import bp as sedes_bp

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
