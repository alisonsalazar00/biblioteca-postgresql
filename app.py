"""Aplicación web de la biblioteca (Flask)."""
import os
import secrets
from datetime import timedelta
from functools import wraps

import psycopg
from flask import (
    Flask,
    abort,
    flash,
    redirect,
    render_template,
    request,
    session,
    url_for,
)

from db import call, query

app = Flask(__name__)

# La clave firma las cookies de sesión. Define SECRET_KEY en el .env con un texto
# largo y aleatorio; la de abajo solo existe para que funcione en desarrollo.
app.secret_key = os.getenv("SECRET_KEY", "clave-solo-para-desarrollo")
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,   # JavaScript no puede leer la cookie
    SESSION_COOKIE_SAMESITE="Lax",  # el navegador no la envía en formularios de otros sitios
    PERMANENT_SESSION_LIFETIME=timedelta(hours=8),
)


# ---------------------------------------------------------------------------
# Filtros de plantilla
# ---------------------------------------------------------------------------
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


@app.template_filter("fechahora")
def formato_fechahora(valor):
    """Muestra una fecha y hora como día/mes/año hora:minutos."""
    return valor.strftime("%d/%m/%Y %H:%M") if valor else ""


# ---------------------------------------------------------------------------
# Seguridad: CSRF, permisos y caché
# ---------------------------------------------------------------------------
def generar_csrf():
    """Token secreto de la sesión que deben traer todos los formularios POST."""
    if "csrf" not in session:
        session["csrf"] = secrets.token_hex(16)
    return session["csrf"]


app.jinja_env.globals["csrf_token"] = generar_csrf


@app.before_request
def proteger_csrf():
    if request.method == "POST":
        esperado = session.get("csrf", "")
        recibido = request.form.get("csrf_token", "")
        if not esperado or not secrets.compare_digest(esperado, recibido):
            abort(400)


@app.after_request
def sin_cache(respuesta):
    # Con sesión iniciada, el navegador no guarda las páginas: al cerrar sesión
    # y usar el botón "atrás" no se ven datos privados.
    if "cuenta_id" in session:
        respuesta.headers["Cache-Control"] = "no-store"
    return respuesta


def acceso(*roles):
    """Exige sesión iniciada y, si se indican roles, que la cuenta tenga alguno."""

    def decorador(vista):
        @wraps(vista)
        def envoltura(*args, **kwargs):
            if "cuenta_id" not in session:
                siguiente = None
                if request.method == "GET":
                    siguiente = request.full_path.rstrip("?")
                return redirect(url_for("login", next=siguiente))
            if roles and session.get("rol") not in roles:
                abort(403)
            return vista(*args, **kwargs)

        return envoltura

    return decorador


def destino_seguro(ruta):
    """Solo acepta rutas internas, para que 'next' no lleve a otro sitio."""
    if ruta and ruta.startswith("/") and not ruta.startswith("//") and "\\" not in ruta:
        return ruta
    return url_for("catalogo")


# ---------------------------------------------------------------------------
# Páginas de error
# ---------------------------------------------------------------------------
@app.errorhandler(400)
def error_400(_):
    return render_template(
        "error.html",
        titulo="Solicitud no válida",
        mensaje="La página caducó o la solicitud no es válida. Vuelve a cargarla e inténtalo de nuevo.",
    ), 400


@app.errorhandler(403)
def error_403(_):
    return render_template(
        "error.html",
        titulo="Sin permiso",
        mensaje="Tu cuenta no tiene permiso para ver esta página.",
    ), 403


@app.errorhandler(404)
def error_404(_):
    return render_template(
        "error.html",
        titulo="Página no encontrada",
        mensaje="La dirección que buscas no existe.",
    ), 404


# ---------------------------------------------------------------------------
# Inicio y cierre de sesión
# ---------------------------------------------------------------------------
@app.route("/")
def inicio():
    return redirect(url_for("catalogo" if "cuenta_id" in session else "login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    if "cuenta_id" in session:
        return redirect(url_for("catalogo"))

    siguiente = request.args.get("next", "")
    identificador = ""

    if request.method == "POST":
        identificador = request.form.get("identificador", "").strip()
        contrasena = request.form.get("contrasena", "")

        # La función SQL comprueba la contraseña, cuenta los intentos fallidos
        # y bloquea la cuenta. Aquí solo se interpreta su resultado.
        fila = call(
            "SELECT * FROM verificar_credenciales(%s, %s)", (identificador, contrasena)
        )

        if fila["r_resultado"] == "ok":
            session.clear()
            session.permanent = True
            session["cuenta_id"] = fila["r_cuenta_id"]
            session["rol"] = fila["r_rol"]
            session["usuario_id"] = fila["r_usuario_id"]
            session["nombre"] = fila["r_nombre"]
            return redirect(destino_seguro(siguiente))

        if fila["r_resultado"] == "bloqueada":
            minutos = fila["r_minutos"]
            unidad = "minuto" if minutos == 1 else "minutos"
            flash(
                f"Demasiados intentos fallidos. Intenta de nuevo en {minutos} {unidad}.",
                "error",
            )
        elif fila["r_resultado"] == "inactiva":
            flash("Tu cuenta está desactivada. Contacta al bibliotecario.", "error")
        else:
            # Mismo mensaje si el usuario no existe o la contraseña falla,
            # para no revelar qué cuentas existen.
            flash("El usuario o la contraseña no son correctos.", "error")

    return render_template("login.html", siguiente=siguiente, identificador=identificador)


@app.route("/logout", methods=["POST"])
def logout():
    session.clear()
    flash("Cerraste sesión.", "exito")
    return redirect(url_for("login"))


@app.route("/cuenta/contrasena", methods=["GET", "POST"])
@acceso()
def cambiar_contrasena():
    if request.method == "POST":
        actual = request.form.get("actual", "")
        nueva = request.form.get("nueva", "")
        confirmar = request.form.get("confirmar", "")

        if nueva != confirmar:
            flash("La contraseña nueva y su confirmación no coinciden.", "error")
            return redirect(url_for("cambiar_contrasena"))

        try:
            call(
                "SELECT cambiar_contrasena(%s, %s, %s)",
                (session["cuenta_id"], actual, nueva),
            )
        except psycopg.errors.RaiseException as error:
            flash(error.diag.message_primary, "error")
            return redirect(url_for("cambiar_contrasena"))

        flash("Contraseña actualizada.", "exito")
        return redirect(url_for("cambiar_contrasena"))

    return render_template("contrasena.html")


# ---------------------------------------------------------------------------
# Catálogo (todas las cuentas)
# ---------------------------------------------------------------------------
@app.route("/catalogo")
@acceso()
def catalogo():
    # La vista v_catalogo ya trae autores, categoría y copias por libro
    libros = query("SELECT * FROM v_catalogo ORDER BY titulo")
    resumen = {
        "titulos": len(libros),
        "copias": sum(l["total_copias"] for l in libros),
        "disponibles": sum(l["copias_disponibles"] for l in libros),
    }
    return render_template("catalogo.html", libros=libros, resumen=resumen)


# ---------------------------------------------------------------------------
# Préstamos y multas (solo bibliotecario)
# ---------------------------------------------------------------------------
def ids_por_correo():
    """Correo -> usuario_id, para enlazar cada fila con el perfil del usuario."""
    return {f["email"]: f["usuario_id"] for f in query("SELECT usuario_id, email FROM usuarios")}


@app.route("/prestamos")
@acceso("bibliotecario")
def prestamos():
    # Los más urgentes (vencidos hace más tiempo) aparecen primero
    filas = query(
        "SELECT * FROM v_prestamos_activos ORDER BY fecha_vencimiento, prestamo_id"
    )
    n_vencidos = sum(1 for f in filas if f["dias_retraso"] > 0)
    return render_template(
        "prestamos.html",
        filas=filas,
        n_vencidos=n_vencidos,
        solo_vencidos=False,
        ids_usuarios=ids_por_correo(),
    )


@app.route("/vencidos")
@acceso("bibliotecario")
def vencidos():
    filas = query(
        "SELECT * FROM v_prestamos_vencidos ORDER BY dias_retraso DESC, prestamo_id"
    )
    return render_template(
        "prestamos.html", filas=filas, solo_vencidos=True, ids_usuarios=ids_por_correo()
    )


@app.route("/prestar", methods=["GET", "POST"])
@acceso("bibliotecario")
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
@acceso("bibliotecario")
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
    usuario_id = request.form.get("usuario_id", type=int)
    if usuario_id:
        return redirect(url_for("perfil_usuario", usuario_id=usuario_id))
    destino = "vencidos" if request.form.get("volver") == "vencidos" else "prestamos"
    return redirect(url_for(destino))


@app.route("/multas")
@acceso("bibliotecario")
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
@acceso("bibliotecario")
def pagar_multa(multa_id):
    try:
        fila = call("SELECT pagar_multa(%s) AS monto", (multa_id,))
    except psycopg.errors.RaiseException as error:
        flash(error.diag.message_primary, "error")
    else:
        flash(f"Pago registrado: {formato_colones(fila['monto'])}.", "exito")
    return redirect(url_for("multas"))


# ---------------------------------------------------------------------------
# Usuarios (solo bibliotecario)
# ---------------------------------------------------------------------------
PROVINCIAS = ["San José", "Alajuela", "Cartago", "Heredia", "Guanacaste", "Puntarenas", "Limón"]
CAMPOS_USUARIO = ("nombre", "apellido", "email", "telefono", "provincia", "canton", "distrito", "direccion")


def contrasena_temporal():
    """Genera una contraseña aleatoria de 10 caracteres, sin letras que se confundan."""
    alfabeto = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    while True:
        clave = "".join(secrets.choice(alfabeto) for _ in range(10))
        if any(c.isdigit() for c in clave) and any(c.isalpha() for c in clave):
            return clave


def mensaje_error(error):
    """Mensaje para mostrar cuando la base de datos rechaza un cambio."""
    if isinstance(error, psycopg.errors.RaiseException):
        return error.diag.message_primary
    return "No se pudo guardar: los datos no cumplen las reglas de la base de datos."


def leer_datos_usuario():
    return {campo: request.form.get(campo, "").strip() for campo in CAMPOS_USUARIO}


@app.route("/usuarios")
@acceso("bibliotecario")
def lista_usuarios():
    filas = query("SELECT * FROM v_usuarios_resumen ORDER BY apellido, nombre")
    n_activos = sum(1 for f in filas if f["activo"])

    # Libros que cada usuario tiene en su poder ahora mismo
    prestados = {}
    en_curso = query(
        """
        SELECT usuario_id, titulo, estado
        FROM v_historial_usuario
        WHERE estado IN ('Activo', 'Vencido')
        ORDER BY fecha_vencimiento, prestamo_id
        """
    )
    for p in en_curso:
        prestados.setdefault(p["usuario_id"], []).append(p)

    return render_template(
        "usuarios.html", filas=filas, n_activos=n_activos, prestados=prestados
    )


@app.route("/usuarios/nuevo", methods=["GET", "POST"])
@acceso("bibliotecario")
def crear_usuario():
    datos = {campo: "" for campo in CAMPOS_USUARIO}

    if request.method == "POST":
        datos = leer_datos_usuario()
        clave = contrasena_temporal()
        try:
            # Crea el usuario y su cuenta en una sola transacción
            fila = call(
                "SELECT crear_usuario_con_cuenta(%s, %s, %s, %s, %s, %s, %s, %s, %s) AS usuario_id",
                (
                    datos["nombre"], datos["apellido"], datos["email"], clave,
                    datos["telefono"], datos["provincia"], datos["canton"],
                    datos["distrito"], datos["direccion"],
                ),
            )
        except (psycopg.errors.RaiseException, psycopg.errors.IntegrityError) as error:
            flash(mensaje_error(error), "error")
        else:
            flash(
                f"Usuario creado. Contraseña temporal: {clave}. "
                "Compártela con la persona; se muestra una sola vez.",
                "exito",
            )
            return redirect(url_for("perfil_usuario", usuario_id=fila["usuario_id"]))

    return render_template(
        "formulario_usuario.html", modo="crear", datos=datos, provincias=PROVINCIAS
    )


@app.route("/usuarios/<int:usuario_id>")
@acceso("bibliotecario")
def perfil_usuario(usuario_id):
    filas = query("SELECT * FROM v_usuarios_resumen WHERE usuario_id = %s", (usuario_id,))
    if not filas:
        abort(404)
    historial = query(
        """
        SELECT * FROM v_historial_usuario
        WHERE usuario_id = %s
        ORDER BY fecha_prestamo DESC, prestamo_id DESC
        """,
        (usuario_id,),
    )
    # v_cuentas nunca incluye la contraseña
    cuentas = query("SELECT * FROM v_cuentas WHERE usuario_id = %s", (usuario_id,))
    prestados = [h for h in historial if h["estado"] in ("Activo", "Vencido")]
    return render_template(
        "perfil_usuario.html",
        u=filas[0],
        historial=historial,
        prestados=prestados,
        cuenta=cuentas[0] if cuentas else None,
    )


@app.route("/usuarios/<int:usuario_id>/editar", methods=["GET", "POST"])
@acceso("bibliotecario")
def editar_usuario(usuario_id):
    filas = query("SELECT * FROM v_usuarios_resumen WHERE usuario_id = %s", (usuario_id,))
    if not filas:
        abort(404)
    u = filas[0]

    if request.method == "POST":
        datos = leer_datos_usuario()
        datos["activo"] = request.form.get("activo") == "on"
        try:
            call(
                "SELECT editar_usuario(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (
                    usuario_id, datos["nombre"], datos["apellido"], datos["email"],
                    datos["telefono"], datos["provincia"], datos["canton"],
                    datos["distrito"], datos["direccion"], datos["activo"],
                ),
            )
        except (psycopg.errors.RaiseException, psycopg.errors.IntegrityError) as error:
            flash(mensaje_error(error), "error")
        else:
            flash("Usuario actualizado.", "exito")
            return redirect(url_for("perfil_usuario", usuario_id=usuario_id))
    else:
        datos = {
            "nombre": u["nombre"],
            "apellido": u["apellido"],
            "email": u["email"],
            "telefono": u["telefono"] or "",
            "provincia": u["provincia"] or "",
            "canton": u["canton"] or "",
            "distrito": u["distrito"] or "",
            "direccion": u["direccion_exacta"] or "",
            "activo": u["activo"],
        }

    return render_template(
        "formulario_usuario.html",
        modo="editar",
        u=u,
        datos=datos,
        provincias=PROVINCIAS,
    )


@app.route("/usuarios/<int:usuario_id>/restablecer", methods=["POST"])
@acceso("bibliotecario")
def restablecer_contrasena(usuario_id):
    cuentas = query("SELECT cuenta_id FROM v_cuentas WHERE usuario_id = %s", (usuario_id,))
    if not cuentas:
        flash("Este usuario no tiene una cuenta de acceso.", "error")
        return redirect(url_for("perfil_usuario", usuario_id=usuario_id))

    # El bibliotecario nunca elige ni ve la contraseña anterior: se genera una nueva
    clave = contrasena_temporal()
    try:
        call(
            "SELECT restablecer_contrasena(%s, %s)", (cuentas[0]["cuenta_id"], clave)
        )
    except psycopg.errors.RaiseException as error:
        flash(mensaje_error(error), "error")
    else:
        flash(
            f"Contraseña restablecida. Nueva contraseña temporal: {clave}. "
            "Compártela con la persona; se muestra una sola vez.",
            "exito",
        )
    return redirect(url_for("perfil_usuario", usuario_id=usuario_id))


if __name__ == "__main__":
    app.run(debug=True)