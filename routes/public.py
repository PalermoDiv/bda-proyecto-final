from flask import render_template, request, redirect, url_for, session, flash
import os


def init_routes(app):

    @app.route("/")
    def index_publico():
        if session.get("admin"):
            return redirect(url_for("dashboard"))
        if session.get("medico"):
            return redirect(url_for("clinica_sedes"))
        return render_template("public.html")

    @app.route("/login", methods=["GET", "POST"])
    def login():
        if request.method == "POST":
            usuario  = request.form["usuario"]
            password = request.form["password"]

            if usuario == os.getenv("ADMIN_USER", "admin") and \
               password == os.getenv("ADMIN_PASSWORD", "admin123"):
                session["admin"] = True
                session["rol"] = "admin"
                return redirect(url_for("dashboard"))

            elif usuario == "medico" and password == "medico123":
                session["medico"] = True
                session["rol"] = "medico"
                return redirect(url_for("clinica_sedes"))

            flash("Usuario o contraseña incorrectos", "error")

        return render_template("login.html")

    @app.route("/logout")
    def logout():
        session.clear()
        return redirect(url_for("index_publico"))
