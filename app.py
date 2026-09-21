"""Aplicación web de la biblioteca (Flask)."""
import os

import psycopg
from flask import Flask, flash, redirect, render_template, request, url_for

from db import call, query

app = Flask(__name__)
# Necesaria para los mensajes de aviso (flash). Puedes definir SECRET_KEY en el .env
app.secret_key = os.getenv("SECRET_KEY", "clave-solo-para-desarrollo")


@app.template_filter("fecha")
def formato_fecha(valor):
    """Muestra una fecha como día/mes/año."""
    return valor.strftime("%d/%m/%Y") if valor else ""


@app.template_filter("dias")
def formato_dias(cantidad):
    """Escribe '1 día' o '5 días' según la cantidad."""
    return f"{cantidad} día" if cantidad == 1 else f"{cantidad} días"


@app.template_filter("colones")
def formato_colones(monto):
    """Muestra un monto como ₡1 200 (espacio como separador de miles)."""
    return "₡" + f"{monto:,.0f}".replace(",", " ")


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


@app.route("/prestar", methods=["GET", "POST"])
def prestar():
    if request.method == "POST":
        try:
            usuario_id = int(request.form["usuario_id"])
            ejemplar_id = int(request.form["ejemplar_id"])
        except (KeyError, ValueError):
            flash("Elige un usuario y un ejemplar para registrar el préstamo.", "error")
            return redirect(url_for("prestar"))

        try:
            # Las reglas (usuario activo, sin multas, ejemplar disponible)
            # las valida la función SQL
            call("SELECT prestar_libro(%s, %s)", (usuario_id, ejemplar_id))
        except psycopg.errors.RaiseException as error:
            flash(error.diag.message_primary, "error")
            return redirect(url_for("prestar"))

        flash("Préstamo registrado. El libro debe devolverse en 14 días.", "exito")
        return redirect(url_for("prestamos"))

    usuarios = query(
        """
        SELECT usuario_id, nombre || ' ' || apellido AS nombre, email
        FROM usuarios
        WHERE activo
        ORDER BY apellido, nombre
        """
    )
    ejemplares = query(
        """
        SELECT e.ejemplar_id, e.codigo_barras, l.titulo
        FROM ejemplares e
        JOIN libros l ON l.libro_id = e.libro_id
        WHERE e.estado = 'disponible'
        ORDER BY l.titulo, e.codigo_barras
        """
    )
    return render_template("prestar.html", usuarios=usuarios, ejemplares=ejemplares)


@app.route("/devolver/<int:prestamo_id>", methods=["POST"])
def devolver(prestamo_id):
    try:
        fila = call("SELECT devolver_libro(%s) AS retraso", (prestamo_id,))
    except psycopg.errors.RaiseException as error:
        flash(error.diag.message_primary, "error")
    else:
        retraso = fila["retraso"]
        if retraso:
            mensaje = f"Devolución registrada con {formato_dias(retraso)} de retraso."
            # Si hubo retraso, el trigger de la base de datos creó una multa
            multa = query(
                "SELECT monto FROM multas WHERE prestamo_id = %s", (prestamo_id,)
            )
            if multa:
                mensaje += f" Se generó una multa de {formato_colones(multa[0]['monto'])}."
            flash(mensaje, "exito")
        else:
            flash("Devolución registrada. El libro se entregó a tiempo.", "exito")

    # Vuelve a la página desde la que se hizo clic
    destino = "vencidos" if request.form.get("volver") == "vencidos" else "prestamos"
    return redirect(url_for(destino))


@app.route("/multas")
def multas():
    # Primero las pendientes, y dentro de cada grupo las más recientes
    filas = query(
        "SELECT * FROM v_multas ORDER BY pagada, fecha_generada DESC, multa_id"
    )
    pendientes = [f for f in filas if not f["pagada"]]
    total_pendiente = sum(f["monto"] for f in pendientes)
    return render_template(
        "multas.html",
        filas=filas,
        n_pendientes=len(pendientes),
        total_pendiente=total_pendiente,
    )


@app.route("/multas/<int:multa_id>/pagar", methods=["POST"])
def pagar_multa(multa_id):
    try:
        fila = call("SELECT pagar_multa(%s) AS monto", (multa_id,))
    except psycopg.errors.RaiseException as error:
        flash(error.diag.message_primary, "error")
    else:
        flash(f"Pago registrado: {formato_colones(fila['monto'])}.", "exito")
    return redirect(url_for("multas"))


if __name__ == "__main__":
    app.run(debug=True)