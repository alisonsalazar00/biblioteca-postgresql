-- =====================================================
-- Sistema de Biblioteca - Cuentas y roles
-- Ejecutar DESPUÉS de 01 a 07.
-- Se puede ejecutar varias veces, pero recrea la tabla de
-- cuentas: se pierden las contraseñas cambiadas y los bloqueos.
--
-- Las cuentas del final son de DEMOSTRACIÓN. En un sistema real
-- nunca se escriben contraseñas dentro de un script.
-- =====================================================

-- pgcrypto aporta crypt() y gen_salt() para cifrar contraseñas con bcrypt.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DROP TABLE IF EXISTS cuentas CASCADE;


-- -----------------------------------------------------
-- Cuentas
-- Hay dos roles:
--   bibliotecario: entra con un nombre de usuario.
--   cliente: entra con el correo de su usuario, así el correo
--            no se guarda dos veces.
-- Nunca se guarda la contraseña, solo su hash bcrypt.
-- -----------------------------------------------------
CREATE TABLE cuentas (
    cuenta_id         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rol               VARCHAR(20) NOT NULL
                      CHECK (rol IN ('bibliotecario', 'cliente')),
    nombre_usuario    VARCHAR(50),
    nombre_visible    VARCHAR(100),
    usuario_id        INT UNIQUE REFERENCES usuarios (usuario_id),
    hash_contrasena   TEXT NOT NULL,
    activa            BOOLEAN NOT NULL DEFAULT TRUE,
    intentos_fallidos INT NOT NULL DEFAULT 0,
    bloqueada_hasta   TIMESTAMPTZ,
    ultimo_acceso     TIMESTAMPTZ,
    fecha_creacion    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Un cliente siempre está ligado a un usuario y no tiene nombre de usuario;
    -- un bibliotecario es lo contrario.
    CHECK (
        (rol = 'cliente'
            AND usuario_id IS NOT NULL
            AND nombre_usuario IS NULL)
        OR
        (rol = 'bibliotecario'
            AND usuario_id IS NULL
            AND nombre_usuario IS NOT NULL
            AND nombre_visible IS NOT NULL)
    ),
    -- Sin @, para que un nombre de usuario nunca coincida con un correo
    CHECK (nombre_usuario IS NULL OR nombre_usuario ~ '^[A-Za-z0-9._-]{3,50}$')
);

CREATE UNIQUE INDEX uq_cuentas_nombre_usuario
    ON cuentas (lower(nombre_usuario))
    WHERE nombre_usuario IS NOT NULL;


-- -----------------------------------------------------
-- validar_contrasena(texto)
-- Mínimo 8 caracteres, con al menos una letra y un número.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION validar_contrasena(p_contrasena TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_contrasena IS NULL OR length(p_contrasena) < 8 THEN
        RAISE EXCEPTION 'La contraseña debe tener al menos 8 caracteres';
    END IF;

    IF p_contrasena !~ '[A-Za-z]' OR p_contrasena !~ '[0-9]' THEN
        RAISE EXCEPTION 'La contraseña debe incluir al menos una letra y un número';
    END IF;
END;
$$;


-- -----------------------------------------------------
-- crear_cuenta_bibliotecario(usuario, nombre, contraseña)
-- Devuelve el id de la cuenta creada.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION crear_cuenta_bibliotecario(
    p_nombre_usuario TEXT,
    p_nombre_visible TEXT,
    p_contrasena     TEXT
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_cuenta_id INT;
BEGIN
    IF p_nombre_usuario IS NULL OR btrim(p_nombre_usuario) !~ '^[A-Za-z0-9._-]{3,50}$' THEN
        RAISE EXCEPTION 'El nombre de usuario debe tener entre 3 y 50 caracteres: letras, números, punto, guion o guion bajo';
    END IF;

    IF btrim(COALESCE(p_nombre_visible, '')) = '' THEN
        RAISE EXCEPTION 'El nombre a mostrar es obligatorio';
    END IF;

    IF EXISTS (SELECT 1 FROM cuentas WHERE lower(nombre_usuario) = lower(btrim(p_nombre_usuario))) THEN
        RAISE EXCEPTION 'Ya existe una cuenta con el nombre de usuario %', btrim(p_nombre_usuario);
    END IF;

    PERFORM validar_contrasena(p_contrasena);

    INSERT INTO cuentas (rol, nombre_usuario, nombre_visible, hash_contrasena)
    VALUES ('bibliotecario',
            btrim(p_nombre_usuario),
            btrim(p_nombre_visible),
            crypt(p_contrasena, gen_salt('bf', 10)))
    RETURNING cuenta_id INTO v_cuenta_id;

    RETURN v_cuenta_id;
END;
$$;


-- -----------------------------------------------------
-- crear_cuenta_cliente(usuario, contraseña)
-- Le da acceso al sistema a un usuario que ya existe.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION crear_cuenta_cliente(
    p_usuario_id INT,
    p_contrasena TEXT
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_cuenta_id INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuarios WHERE usuario_id = p_usuario_id) THEN
        RAISE EXCEPTION 'El usuario % no existe', p_usuario_id;
    END IF;

    IF EXISTS (SELECT 1 FROM cuentas WHERE usuario_id = p_usuario_id) THEN
        RAISE EXCEPTION 'El usuario % ya tiene una cuenta', p_usuario_id;
    END IF;

    PERFORM validar_contrasena(p_contrasena);

    INSERT INTO cuentas (rol, usuario_id, hash_contrasena)
    VALUES ('cliente', p_usuario_id, crypt(p_contrasena, gen_salt('bf', 10)))
    RETURNING cuenta_id INTO v_cuenta_id;

    RETURN v_cuenta_id;
END;
$$;


-- -----------------------------------------------------
-- crear_usuario_con_cuenta(...)
-- Crea el usuario y su cuenta en un solo paso. Como es una
-- sola función, es una sola transacción: si algo falla, no
-- queda un usuario creado sin cuenta.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION crear_usuario_con_cuenta(
    p_nombre     TEXT,
    p_apellido   TEXT,
    p_email      TEXT,
    p_contrasena TEXT,
    p_telefono   TEXT DEFAULT NULL,
    p_provincia  TEXT DEFAULT NULL,
    p_canton     TEXT DEFAULT NULL,
    p_distrito   TEXT DEFAULT NULL,
    p_direccion  TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_usuario_id INT;
BEGIN
    PERFORM validar_contrasena(p_contrasena);

    v_usuario_id := crear_usuario(p_nombre, p_apellido, p_email, p_telefono,
                                  p_provincia, p_canton, p_distrito, p_direccion);

    PERFORM crear_cuenta_cliente(v_usuario_id, p_contrasena);

    RETURN v_usuario_id;
END;
$$;


-- -----------------------------------------------------
-- verificar_credenciales(identificador, contraseña)
-- Es la función que usa el inicio de sesión. Devuelve SIEMPRE
-- una fila con el resultado: ok, incorrecto, inactiva o bloqueada.
--
-- No lanza errores a propósito: un error deshace la transacción
-- y con ella se perdería el conteo de intentos fallidos.
--
-- A los 5 intentos fallidos la cuenta se bloquea 15 minutos.
-- Cuando el usuario o la contraseña no coinciden, el resultado es
-- el mismo ("incorrecto"), así no se revela si la cuenta existe.
-- El hash nunca sale de esta función.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION verificar_credenciales(
    p_identificador TEXT,
    p_contrasena    TEXT
)
RETURNS TABLE (
    r_resultado  TEXT,
    r_cuenta_id  INT,
    r_rol        TEXT,
    r_usuario_id INT,
    r_nombre     TEXT,
    r_minutos    INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    c              RECORD;
    v_max_intentos CONSTANT INT := 5;
    v_bloqueo      CONSTANT INTERVAL := INTERVAL '15 minutes';
BEGIN
    SELECT ct.cuenta_id,
           ct.rol,
           ct.usuario_id,
           ct.hash_contrasena,
           ct.activa,
           ct.intentos_fallidos,
           ct.bloqueada_hasta,
           COALESCE(ct.nombre_visible, u.nombre || ' ' || u.apellido) AS nombre,
           COALESCE(u.activo, TRUE) AS usuario_activo
    INTO c
    FROM cuentas ct
    LEFT JOIN usuarios u ON u.usuario_id = ct.usuario_id
    WHERE lower(COALESCE(ct.nombre_usuario, u.email)) = lower(btrim(COALESCE(p_identificador, '')))
    FOR UPDATE OF ct;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'incorrecto'::TEXT, NULL::INT, NULL::TEXT, NULL::INT, NULL::TEXT, NULL::INT;
        RETURN;
    END IF;

    IF NOT c.activa OR NOT c.usuario_activo THEN
        RETURN QUERY SELECT 'inactiva'::TEXT, NULL::INT, NULL::TEXT, NULL::INT, NULL::TEXT, NULL::INT;
        RETURN;
    END IF;

    IF c.bloqueada_hasta IS NOT NULL AND c.bloqueada_hasta > now() THEN
        RETURN QUERY SELECT 'bloqueada'::TEXT, NULL::INT, NULL::TEXT, NULL::INT, NULL::TEXT,
                            CEIL(EXTRACT(EPOCH FROM (c.bloqueada_hasta - now())) / 60)::INT;
        RETURN;
    END IF;

    -- crypt() con el hash guardado como "sal" repite el cifrado y lo compara
    IF c.hash_contrasena = crypt(COALESCE(p_contrasena, ''), c.hash_contrasena) THEN
        UPDATE cuentas
        SET intentos_fallidos = 0,
            bloqueada_hasta   = NULL,
            ultimo_acceso     = now()
        WHERE cuenta_id = c.cuenta_id;

        RETURN QUERY SELECT 'ok'::TEXT, c.cuenta_id, c.rol::TEXT, c.usuario_id, c.nombre::TEXT, NULL::INT;
        RETURN;
    END IF;

    -- Contraseña incorrecta
    IF c.intentos_fallidos + 1 >= v_max_intentos THEN
        UPDATE cuentas
        SET intentos_fallidos = 0,
            bloqueada_hasta   = now() + v_bloqueo
        WHERE cuenta_id = c.cuenta_id;

        RETURN QUERY SELECT 'bloqueada'::TEXT, NULL::INT, NULL::TEXT, NULL::INT, NULL::TEXT, 15;
    ELSE
        UPDATE cuentas
        SET intentos_fallidos = intentos_fallidos + 1
        WHERE cuenta_id = c.cuenta_id;

        RETURN QUERY SELECT 'incorrecto'::TEXT, NULL::INT, NULL::TEXT, NULL::INT, NULL::TEXT, NULL::INT;
    END IF;
END;
$$;


-- -----------------------------------------------------
-- cambiar_contrasena(cuenta, actual, nueva)
-- La persona cambia su propia contraseña.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION cambiar_contrasena(
    p_cuenta_id INT,
    p_actual    TEXT,
    p_nueva     TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_hash TEXT;
BEGIN
    SELECT hash_contrasena INTO v_hash
    FROM cuentas
    WHERE cuenta_id = p_cuenta_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cuenta % no existe', p_cuenta_id;
    END IF;

    IF v_hash <> crypt(COALESCE(p_actual, ''), v_hash) THEN
        RAISE EXCEPTION 'La contraseña actual no es correcta';
    END IF;

    PERFORM validar_contrasena(p_nueva);

    UPDATE cuentas
    SET hash_contrasena = crypt(p_nueva, gen_salt('bf', 10))
    WHERE cuenta_id = p_cuenta_id;
END;
$$;


-- -----------------------------------------------------
-- restablecer_contrasena(cuenta, nueva)
-- La usa el bibliotecario cuando alguien olvidó su contraseña.
-- También quita el bloqueo. Nadie puede VER la contraseña
-- anterior: solo se puede reemplazar por una nueva.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION restablecer_contrasena(
    p_cuenta_id INT,
    p_nueva     TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cuentas WHERE cuenta_id = p_cuenta_id) THEN
        RAISE EXCEPTION 'La cuenta % no existe', p_cuenta_id;
    END IF;

    PERFORM validar_contrasena(p_nueva);

    UPDATE cuentas
    SET hash_contrasena   = crypt(p_nueva, gen_salt('bf', 10)),
        intentos_fallidos = 0,
        bloqueada_hasta   = NULL
    WHERE cuenta_id = p_cuenta_id;
END;
$$;


-- -----------------------------------------------------
-- v_cuentas
-- Las cuentas SIN la contraseña. Esta es la única forma en que
-- la aplicación lista cuentas: el hash no aparece en ninguna vista.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_cuentas AS
SELECT
    c.cuenta_id,
    c.rol,
    COALESCE(c.nombre_usuario, u.email)                        AS acceso,
    COALESCE(c.nombre_visible, u.nombre || ' ' || u.apellido)  AS nombre,
    c.usuario_id,
    c.activa,
    (c.bloqueada_hasta IS NOT NULL AND c.bloqueada_hasta > now()) AS bloqueada,
    c.ultimo_acceso,
    c.fecha_creacion
FROM cuentas c
LEFT JOIN usuarios u ON u.usuario_id = c.usuario_id;


-- -----------------------------------------------------
-- Cuentas de demostración
--   Bibliotecario:  usuario  bibliotecario   contraseña  Biblioteca2026
--   Clientes:       su correo (por ejemplo sofia.jimenez@example.com)
--                   contraseña  Cliente2026
-- -----------------------------------------------------
SELECT crear_cuenta_bibliotecario('bibliotecario', 'Bibliotecario Principal', 'Biblioteca2026');

SELECT crear_cuenta_cliente(usuario_id, 'Cliente2026')
FROM usuarios
ORDER BY usuario_id;
