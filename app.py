"""Aplicación web de la biblioteca (Flask)."""
from flask import Flask, redirect, render_template, url_for

from db import query

app = Flask(__name__)


@app.template_filter("fecha")
def formato_fecha(valor):
    """Muestra una fecha como día/mes/año."""
    return valor.strftime("%d/%m/%Y") if valor else ""


@app.template_filter("dias")
def formato_dias(cantidad):
    """Escribe '1 día' o '5 días' según la cantidad."""
    return f"{cantidad} día" if cantidad == 1 else f"{cantidad} días"


@app.route("/")
def inicio():
    return redirect(url_for("catalogo"))


@app.route("/catalogo")
def catalogo():
    # La vista v_catalogo ya trae autores, categoría y copias por libro
    libros = query("SELECT * FROM v_catalogo ORDER BY titulo")
    resumen = {
        "titulos": len(libros),
        "copias": sum(l["total_copias"] for l in libros),
        "disponibles": sum(l["copias_disponibles"] for l in libros),
    }
    return render_template("catalogo.html", libros=libros, resumen=resumen)


@app.route("/prestamos")
def prestamos():
    # Los más urgentes (vencidos hace más tiempo) aparecen primero
    filas = query(
        "SELECT * FROM v_prestamos_activos ORDER BY fecha_vencimiento, prestamo_id"
    )
    n_vencidos = sum(1 for f in filas if f["dias_retraso"] > 0)
    return render_template(
        "prestamos.html", filas=filas, n_vencidos=n_vencidos, solo_vencidos=False
    )


@app.route("/vencidos")
def vencidos():
    filas = query(
        "SELECT * FROM v_prestamos_vencidos ORDER BY dias_retraso DESC, prestamo_id"
    )
    return render_template("prestamos.html", filas=filas, solo_vencidos=True)


if __name__ == "__main__":
    app.run(debug=True)