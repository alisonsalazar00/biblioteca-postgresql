"""Aplicación web de la biblioteca (Flask)."""
import os
import re
import secrets
from datetime import date, timedelta, timezone
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

from db import call as ejecutar_funcion
from db import query

app = Flask(__name__)


def call(sql, params=None):
    """Ejecuta una función SQL a nombre de la cuenta con la sesión iniciada.

    Así todos los cambios quedan en la auditoría con su responsable, sin tener
    que acordarse de pasarlo en cada ruta.
    """
    return ejecutar_funcion(sql, params, cuenta_id=session.get("cuenta_id"))


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


@app.template_filter("pct")
def formato_porcentaje(valor):
    """Muestra un porcentaje con coma decimal: 42,9 %."""
    return f"{(valor or 0):.1f}".replace(".", ",") + " %"


# Costa Rica no usa horario de verano, así que un desfase fijo de -6 horas basta
# y no depende de la base de datos de zonas horarias del sistema.
ZONA_LOCAL = timezone(timedelta(hours=-6))


@app.template_filter("fechahora")
def formato_fechahora(valor):
    """Muestra una fecha y hora (en hora de Costa Rica) como día/mes/año hora:minutos."""
    if not valor:
        return ""
    if valor.tzinfo is not None:
        valor = valor.astimezone(ZONA_LOCAL)
    return valor.strftime("%d/%m/%Y %H:%M")


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


def pagina_inicial():
    """A dónde llega cada rol después de iniciar sesión."""
    return url_for("mis_libros" if session.get("rol") == "cliente" else "panel")


def destino_seguro(ruta):
    """Solo acepta rutas internas, para que 'next' no lleve a otro sitio."""
    if ruta and ruta.startswith("/") and not ruta.startswith("//") and "\\" not in ruta:
        return ruta
    return pagina_inicial()


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
    return redirect(pagina_inicial() if "cuenta_id" in session else url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    if "cuenta_id" in session:
        return redirect(pagina_inicial())

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


# ---------------------------------------------------------------------------
# Vista del cliente
# Todas estas páginas usan el usuario de la SESIÓN. Ninguna recibe un id por la
# dirección web, así que un cliente no puede pedir los datos de otra persona.
# ---------------------------------------------------------------------------
def usuario_de_sesion():
    usuario_id = session.get("usuario_id")
    if usuario_id is None:
        abort(403)
    return usuario_id


@app.route("/mis-libros")
@acceso("cliente")
def mis_libros():
    usuario_id = usuario_de_sesion()
    resumen = query("SELECT * FROM v_usuarios_resumen WHERE usuario_id = %s", (usuario_id,))
    if not resumen:
        abort(404)
    historial = query(
        """
        SELECT * FROM v_historial_usuario
        WHERE usuario_id = %s
        ORDER BY fecha_prestamo DESC, prestamo_id DESC
        """,
        (usuario_id,),
    )
    prestados = [h for h in historial if h["estado"] in ("Activo", "Vencido")]
    return render_template(
        "mis_libros.html", u=resumen[0], historial=historial, prestados=prestados
    )


@app.route("/mis-multas")
@acceso("cliente")
def mis_multas():
    usuario_id = usuario_de_sesion()
    filas = query(
        """
        SELECT * FROM v_multas
        WHERE usuario_id = %s
        ORDER BY pagada, fecha_generada DESC, multa_id
        """,
        (usuario_id,),
    )
    pendientes = [f for f in filas if not f["pagada"]]
    tarifa = query("SELECT valor FROM parametros WHERE clave = 'multa_por_dia'")
    return render_template(
        "mis_multas.html",
        filas=filas,
        n_pendientes=len(pendientes),
        total_pendiente=sum(f["monto"] for f in pendientes),
        tarifa=tarifa[0]["valor"] if tarifa else None,
    )


@app.route("/mi-perfil")
@acceso("cliente")
def mi_perfil():
    usuario_id = usuario_de_sesion()
    resumen = query("SELECT * FROM v_usuarios_resumen WHERE usuario_id = %s", (usuario_id,))
    if not resumen:
        abort(404)
    return render_template("mi_perfil.html", u=resumen[0])


# ---------------------------------------------------------------------------
# Correcciones y auditoría (solo bibliotecario)
# ---------------------------------------------------------------------------
ETIQUETAS_CAMPOS = {
    "nombre": "Nombre",
    "apellido": "Apellido",
    "email": "Correo",
    "telefono": "Teléfono",
    "provincia": "Provincia",
    "canton": "Cantón",
    "distrito": "Distrito",
    "direccion_exacta": "Señas",
    "activo": "Activo",
    "fecha_devolucion": "Fecha de devolución",
    "pagada": "Pagada",
    "fecha_pago": "Fecha de pago",
}


def _valor_auditoria(valor):
    """Escribe un valor guardado en el historial de forma legible."""
    if valor is None or valor == "":
        return "vacío"
    if isinstance(valor, bool):
        return "Sí" if valor else "No"
    if isinstance(valor, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", valor):
        return f"{valor[8:10]}/{valor[5:7]}/{valor[0:4]}"
    return str(valor)


def detalle_auditoria(f):
    """Convierte un registro del historial en líneas de texto: qué cambió."""
    antes = f["datos_anteriores"] or {}
    despues = f["datos_nuevos"] or {}
    evento = f["evento"]
    lineas = []

    if evento == "Préstamo corregido":
        if f["usuario_anterior"] and f["usuario_nuevo"] and f["usuario_anterior"] != f["usuario_nuevo"]:
            lineas.append(f"Usuario: {f['usuario_anterior']} → {f['usuario_nuevo']}")
        if f["ejemplar_anterior"] and f["ejemplar_nuevo"] and f["ejemplar_anterior"] != f["ejemplar_nuevo"]:
            lineas.append(f"Ejemplar: {f['ejemplar_anterior']} → {f['ejemplar_nuevo']}")
    elif evento == "Préstamo registrado":
        lineas.append(f"Vence el {_valor_auditoria(despues.get('fecha_vencimiento'))}")
    elif evento == "Devolución registrada":
        lineas.append(f"Devuelto el {_valor_auditoria(despues.get('fecha_devolucion'))}")
    elif evento == "Multa generada":
        retraso = formato_dias(despues.get("dias_retraso", 0))
        lineas.append(f"{retraso} de retraso, {formato_colones(despues.get('monto', 0))}")
    elif evento == "Multa pagada":
        lineas.append(f"Pagada el {_valor_auditoria(despues.get('fecha_pago'))}")
    elif evento == "Pago de multa anulado":
        lineas.append("De pagada a pendiente")
    elif evento == "Usuario creado":
        lineas.append(f"Correo: {despues.get('email', '')}")
    elif f["operacion"] == "UPDATE":
        for campo, nuevo in despues.items():
            etiqueta = ETIQUETAS_CAMPOS.get(campo, campo)
            lineas.append(f"{etiqueta}: {_valor_auditoria(antes.get(campo))} → {_valor_auditoria(nuevo)}")
    return lineas


@app.route("/auditoria")
@acceso("bibliotecario")
def auditoria():
    eventos = [f["evento"] for f in query("SELECT DISTINCT evento FROM v_auditoria ORDER BY evento")]
    evento = request.args.get("evento", "").strip()

    # Solo se filtra por eventos que existen; cualquier otro valor se ignora
    if evento in eventos:
        filas = query(
            "SELECT * FROM v_auditoria WHERE evento = %s ORDER BY auditoria_id DESC LIMIT 300",
            (evento,),
        )
    else:
        evento = ""
        filas = query("SELECT * FROM v_auditoria ORDER BY auditoria_id DESC LIMIT 300")

    for f in filas:
        f["detalle"] = detalle_auditoria(f)

    return render_template(
        "auditoria.html", filas=filas, eventos=eventos, evento=evento
    )


@app.route("/prestamos/<int:prestamo_id>/corregir", methods=["GET", "POST"])
@acceso("bibliotecario")
def corregir_prestamo(prestamo_id):
    filas = query(
        """
        SELECT p.prestamo_id, p.usuario_id, p.ejemplar_id, p.fecha_prestamo,
               p.fecha_vencimiento, p.fecha_devolucion,
               u.nombre || ' ' || u.apellido AS usuario,
               e.codigo_barras, l.titulo
        FROM prestamos p
        JOIN usuarios   u ON u.usuario_id  = p.usuario_id
        JOIN ejemplares e ON e.ejemplar_id = p.ejemplar_id
        JOIN libros     l ON l.libro_id    = e.libro_id
        WHERE p.prestamo_id = %s
        """,
        (prestamo_id,),
    )
    if not filas:
        abort(404)
    p = filas[0]

    if p["fecha_devolucion"] is not None:
        flash("Este préstamo ya fue devuelto y no se puede corregir.", "error")
        return redirect(url_for("prestamos"))

    seleccion = {"usuario_id": p["usuario_id"], "ejemplar_id": p["ejemplar_id"], "motivo": ""}

    if request.method == "POST":
        try:
            seleccion = {
                "usuario_id": int(request.form["usuario_id"]),
                "ejemplar_id": int(request.form["ejemplar_id"]),
                "motivo": request.form.get("motivo", "").strip(),
            }
        except (KeyError, ValueError):
            flash("Elige un usuario y un ejemplar.", "error")
        else:
            try:
                call(
                    "SELECT corregir_prestamo(%s, %s, %s, %s)",
                    (prestamo_id, seleccion["usuario_id"], seleccion["ejemplar_id"], seleccion["motivo"]),
                )
            except (psycopg.errors.RaiseException, psycopg.errors.IntegrityError) as error:
                flash(mensaje_error(error), "error")
            else:
                flash("Préstamo corregido. El cambio quedó registrado en el historial.", "exito")
                return redirect(url_for("prestamos"))

    # Se incluyen el usuario y el ejemplar actuales aunque ya no cumplan las
    # condiciones normales (por ejemplo, el ejemplar que hoy figura como prestado).
    usuarios = query(
        """
        SELECT usuario_id, nombre || ' ' || apellido AS nombre, email
        FROM usuarios
        WHERE activo OR usuario_id = %s
        ORDER BY apellido, nombre
        """,
        (p["usuario_id"],),
    )
    ejemplares = query(
        """
        SELECT e.ejemplar_id, e.codigo_barras, l.titulo
        FROM ejemplares e
        JOIN libros l ON l.libro_id = e.libro_id
        WHERE e.estado = 'disponible' OR e.ejemplar_id = %s
        ORDER BY l.titulo, e.codigo_barras
        """,
        (p["ejemplar_id"],),
    )
    return render_template(
        "corregir_prestamo.html", p=p, usuarios=usuarios, ejemplares=ejemplares, seleccion=seleccion
    )


@app.route("/multas/<int:multa_id>/anular", methods=["GET", "POST"])
@acceso("bibliotecario")
def anular_pago(multa_id):
    filas = query("SELECT * FROM v_multas WHERE multa_id = %s", (multa_id,))
    if not filas:
        abort(404)
    multa = filas[0]

    if not multa["pagada"]:
        flash("Esta multa no está pagada, no hay un pago que anular.", "error")
        return redirect(url_for("multas"))

    motivo = ""
    if request.method == "POST":
        motivo = request.form.get("motivo", "").strip()
        try:
            call("SELECT anular_pago_multa(%s, %s)", (multa_id, motivo))
        except (psycopg.errors.RaiseException, psycopg.errors.IntegrityError) as error:
            flash(mensaje_error(error), "error")
        else:
            flash(
                "Pago anulado. La multa volvió a estar pendiente y el cambio quedó registrado.",
                "exito",
            )
            return redirect(url_for("multas"))

    return render_template("anular_pago.html", m=multa, motivo=motivo)


# ---------------------------------------------------------------------------
# Panel del bibliotecario
# ---------------------------------------------------------------------------
MESES_ABREVIADOS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]


@app.route("/panel")
@acceso("bibliotecario")
def panel():
    # Las cifras y rankings los calculan las vistas de 10_panel.sql
    resumen = query("SELECT * FROM v_panel_resumen")[0]
    meses = query("SELECT * FROM v_prestamos_por_mes ORDER BY mes")
    libros = query("SELECT * FROM v_ranking_libros ORDER BY posicion, titulo LIMIT 5")
    categorias = query("SELECT * FROM v_uso_categorias ORDER BY prestamos DESC, categoria")
    vencidos = query("SELECT * FROM v_prestamos_vencidos ORDER BY dias_retraso DESC, prestamo_id LIMIT 5")
    con_retrasos = query(
        """
        SELECT usuario_id, nombre_completo, devoluciones_tardias, prestamos_vencidos
        FROM v_usuarios_resumen
        WHERE devoluciones_tardias + prestamos_vencidos > 0
        ORDER BY devoluciones_tardias + prestamos_vencidos DESC, apellido
        LIMIT 5
        """
    )
    actividad = query("SELECT * FROM v_auditoria ORDER BY auditoria_id DESC LIMIT 6")

    # Alturas relativas para dibujar las barras (la más alta ocupa el 100 %)
    maximo_mes = max((m["prestamos"] for m in meses), default=0) or 1
    for i, m in enumerate(meses):
        m["altura"] = round(100 * m["prestamos"] / maximo_mes)
        m["etiqueta"] = MESES_ABREVIADOS[m["mes"].month - 1]
        m["anio"] = f"{m['mes'].year}" if (i == 0 or m["mes"].month == 1) else ""

    maximo_libro = max((l["veces_prestado"] for l in libros), default=0) or 1
    for l in libros:
        l["ancho"] = round(100 * l["veces_prestado"] / maximo_libro)

    return render_template(
        "panel.html",
        r=resumen,
        meses=meses,
        mes_actual=meses[-1] if meses else None,
        libros=libros,
        categorias=categorias,
        vencidos=vencidos,
        con_retrasos=con_retrasos,
        actividad=actividad,
        hoy=date.today(),
    )


if __name__ == "__main__":
    app.run(debug=True)
