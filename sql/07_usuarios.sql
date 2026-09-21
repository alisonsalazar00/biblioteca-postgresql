-- =====================================================
-- Sistema de Biblioteca - Usuarios
-- Dirección, reglas para crear y editar, y vistas de
-- resumen e historial.
-- Ejecutar DESPUÉS de 01 a 06.
-- Se puede ejecutar varias veces sin problema.
-- =====================================================


-- -----------------------------------------------------
-- 1. Columnas de dirección (formato de Costa Rica)
-- Es una "migración": modifica una tabla que ya existe
-- y tiene datos, en lugar de recrearla.
-- -----------------------------------------------------
ALTER TABLE usuarios
    ADD COLUMN IF NOT EXISTS provincia        VARCHAR(20),
    ADD COLUMN IF NOT EXISTS canton           VARCHAR(60),
    ADD COLUMN IF NOT EXISTS distrito         VARCHAR(60),
    ADD COLUMN IF NOT EXISTS direccion_exacta VARCHAR(250);


-- -----------------------------------------------------
-- 2. Direcciones de prueba (ficticias)
-- -----------------------------------------------------
UPDATE usuarios u
SET provincia        = v.provincia,
    canton           = v.canton,
    distrito         = v.distrito,
    direccion_exacta = v.senas
FROM (VALUES
    ('sofia.jimenez@example.com',   'Heredia',    'Heredia',    'San Francisco', '150 m este del parque, casa de portón negro'),
    ('andres.mora@example.com',     'San José',   'Escazú',     'San Rafael',    'Urbanización Los Laureles, casa 14'),
    ('valeria.rojas@example.com',   'Alajuela',   'Alajuela',   'San Rafael',    '300 m sur de la escuela, casa esquinera'),
    ('diego.vargas@example.com',    'Cartago',    'Cartago',    'Oriental',      'Contiguo a la plaza de deportes, apartamento 3'),
    ('camila.solis@example.com',    'Heredia',    'Barva',      'San Pedro',     '400 m norte de la iglesia, casa color celeste'),
    ('daniel.araya@example.com',    'Guanacaste', 'Liberia',    'Liberia',       'Barrio Los Ángeles, 100 m oeste del parque'),
    ('paola.chaves@example.com',    'Puntarenas', 'Puntarenas', 'Barranca',      '200 m sur del colegio, casa verde'),
    ('esteban.quesada@example.com', 'San José',   'Curridabat', 'Curridabat',    'Residencial Vista Real, casa 7'),
    ('lucia.hernandez@example.com', 'Limón',      'Limón',      'Limón',         'Barrio Roosevelt, frente a la cancha'),
    ('mateo.salas@example.com',     'Alajuela',   'San Ramón',  'San Ramón',     '250 m oeste de la iglesia, casa de dos pisos')
) AS v(email, provincia, canton, distrito, senas)
WHERE u.email = v.email;


-- -----------------------------------------------------
-- 3. Restricciones sobre los datos del usuario
-- Son la última línea de defensa: aunque alguien inserte
-- datos sin pasar por las funciones, la base los rechaza.
-- -----------------------------------------------------
ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS ck_usuarios_provincia;
ALTER TABLE usuarios ADD CONSTRAINT ck_usuarios_provincia
    CHECK (provincia IN ('San José', 'Alajuela', 'Cartago', 'Heredia',
                         'Guanacaste', 'Puntarenas', 'Limón'));

ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS ck_usuarios_email_formato;
ALTER TABLE usuarios ADD CONSTRAINT ck_usuarios_email_formato
    CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$');

ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS ck_usuarios_telefono_formato;
ALTER TABLE usuarios ADD CONSTRAINT ck_usuarios_telefono_formato
    CHECK (telefono IS NULL OR telefono ~ '^[0-9]{4}-[0-9]{4}$');

-- El UNIQUE original distingue mayúsculas: 'Ana@x.com' y 'ana@x.com'
-- serían distintos. Este índice los trata como el mismo correo.
CREATE UNIQUE INDEX IF NOT EXISTS uq_usuarios_email_minuscula
    ON usuarios (lower(email));


-- -----------------------------------------------------
-- normalizar_telefono(texto)
-- Acepta '88123456', '8812 3456' o '8812-3456' y lo deja
-- siempre como '8812-3456'. Un texto vacío se guarda como NULL.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION normalizar_telefono(p_telefono TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_digitos TEXT;
BEGIN
    IF p_telefono IS NULL OR btrim(p_telefono) = '' THEN
        RETURN NULL;
    END IF;

    v_digitos := regexp_replace(p_telefono, '[^0-9]', '', 'g');

    IF length(v_digitos) <> 8 THEN
        RAISE EXCEPTION 'El teléfono debe tener 8 dígitos, por ejemplo 8812-3456';
    END IF;

    RETURN substr(v_digitos, 1, 4) || '-' || substr(v_digitos, 5, 4);
END;
$$;


-- -----------------------------------------------------
-- validar_datos_usuario(...)
-- Validaciones compartidas por crear_usuario y editar_usuario.
-- Lanza errores con mensajes claros para mostrarlos en pantalla.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION validar_datos_usuario(
    p_nombre    TEXT,
    p_apellido  TEXT,
    p_email     TEXT,
    p_provincia TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF btrim(COALESCE(p_nombre, '')) = '' OR btrim(COALESCE(p_apellido, '')) = '' THEN
        RAISE EXCEPTION 'El nombre y el apellido son obligatorios';
    END IF;

    IF btrim(COALESCE(p_email, '')) = '' THEN
        RAISE EXCEPTION 'El correo es obligatorio';
    END IF;

    IF btrim(p_email) !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
        RAISE EXCEPTION 'El correo % no tiene un formato válido', btrim(p_email);
    END IF;

    IF NULLIF(btrim(COALESCE(p_provincia, '')), '') IS NOT NULL
       AND btrim(p_provincia) <> ALL (ARRAY['San José', 'Alajuela', 'Cartago', 'Heredia',
                                            'Guanacaste', 'Puntarenas', 'Limón']) THEN
        RAISE EXCEPTION 'La provincia "%" no es válida', btrim(p_provincia);
    END IF;
END;
$$;


-- -----------------------------------------------------
-- crear_usuario(...)
-- Registra un usuario nuevo y devuelve su id.
-- Uso: SELECT crear_usuario('Ana', 'Rojas', 'ana@correo.com', '8800-1122',
--                           'Heredia', 'Barva', 'San Pedro', 'Casa azul');
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION crear_usuario(
    p_nombre    TEXT,
    p_apellido  TEXT,
    p_email     TEXT,
    p_telefono  TEXT DEFAULT NULL,
    p_provincia TEXT DEFAULT NULL,
    p_canton    TEXT DEFAULT NULL,
    p_distrito  TEXT DEFAULT NULL,
    p_direccion TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_usuario_id INT;
BEGIN
    PERFORM validar_datos_usuario(p_nombre, p_apellido, p_email, p_provincia);

    IF EXISTS (SELECT 1 FROM usuarios WHERE lower(email) = lower(btrim(p_email))) THEN
        RAISE EXCEPTION 'Ya existe un usuario con el correo %', lower(btrim(p_email));
    END IF;

    INSERT INTO usuarios (nombre, apellido, email, telefono,
                          provincia, canton, distrito, direccion_exacta)
    VALUES (btrim(p_nombre),
            btrim(p_apellido),
            lower(btrim(p_email)),
            normalizar_telefono(p_telefono),
            NULLIF(btrim(COALESCE(p_provincia, '')), ''),
            NULLIF(btrim(COALESCE(p_canton, '')), ''),
            NULLIF(btrim(COALESCE(p_distrito, '')), ''),
            NULLIF(btrim(COALESCE(p_direccion, '')), ''))
    RETURNING usuario_id INTO v_usuario_id;

    RETURN v_usuario_id;
END;
$$;


-- -----------------------------------------------------
-- editar_usuario(...)
-- Actualiza los datos de un usuario. Regla: no se puede
-- desactivar a alguien que todavía tiene préstamos activos.
-- Los usuarios nunca se borran, se desactivan, para no perder
-- su historial.
-- Uso: SELECT editar_usuario(3, 'Ana', 'Rojas', 'ana@correo.com', '8800-1122',
--                            'Heredia', 'Barva', 'San Pedro', 'Casa azul', TRUE);
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION editar_usuario(
    p_usuario_id INT,
    p_nombre     TEXT,
    p_apellido   TEXT,
    p_email      TEXT,
    p_telefono   TEXT,
    p_provincia  TEXT,
    p_canton     TEXT,
    p_distrito   TEXT,
    p_direccion  TEXT,
    p_activo     BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_activo_actual BOOLEAN;
    v_nuevo_activo  BOOLEAN;
    v_prestamos_activos INT;
BEGIN
    SELECT activo INTO v_activo_actual
    FROM usuarios
    WHERE usuario_id = p_usuario_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El usuario % no existe', p_usuario_id;
    END IF;

    PERFORM validar_datos_usuario(p_nombre, p_apellido, p_email, p_provincia);

    IF EXISTS (
        SELECT 1
        FROM usuarios
        WHERE lower(email) = lower(btrim(p_email))
          AND usuario_id <> p_usuario_id
    ) THEN
        RAISE EXCEPTION 'Ya existe otro usuario con el correo %', lower(btrim(p_email));
    END IF;

    v_nuevo_activo := COALESCE(p_activo, v_activo_actual);

    IF v_activo_actual AND NOT v_nuevo_activo THEN
        SELECT COUNT(*) INTO v_prestamos_activos
        FROM prestamos
        WHERE usuario_id = p_usuario_id
          AND fecha_devolucion IS NULL;

        IF v_prestamos_activos > 0 THEN
            RAISE EXCEPTION
                'El usuario tiene % préstamo(s) activo(s). Registra las devoluciones antes de desactivarlo',
                v_prestamos_activos;
        END IF;
    END IF;

    UPDATE usuarios
    SET nombre           = btrim(p_nombre),
        apellido         = btrim(p_apellido),
        email            = lower(btrim(p_email)),
        telefono         = normalizar_telefono(p_telefono),
        provincia        = NULLIF(btrim(COALESCE(p_provincia, '')), ''),
        canton           = NULLIF(btrim(COALESCE(p_canton, '')), ''),
        distrito         = NULLIF(btrim(COALESCE(p_distrito, '')), ''),
        direccion_exacta = NULLIF(btrim(COALESCE(p_direccion, '')), ''),
        activo           = v_nuevo_activo
    WHERE usuario_id = p_usuario_id;
END;
$$;


-- -----------------------------------------------------
-- v_usuarios_resumen
-- Cada usuario con su dirección completa y sus estadísticas:
-- préstamos totales, activos, vencidos, devoluciones tardías
-- y multas pendientes. Los conteos se calculan en subconsultas
-- ya agrupadas, para que un JOIN no multiplique las filas.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_usuarios_resumen AS
SELECT
    u.usuario_id,
    u.nombre,
    u.apellido,
    u.nombre || ' ' || u.apellido AS nombre_completo,
    u.email,
    u.telefono,
    u.provincia,
    u.canton,
    u.distrito,
    u.direccion_exacta,
    concat_ws(', ', u.direccion_exacta, u.distrito, u.canton, u.provincia) AS direccion,
    u.fecha_registro,
    u.activo,
    COALESCE(p.n_total, 0)     AS total_prestamos,
    COALESCE(p.n_activos, 0)   AS prestamos_activos,
    COALESCE(p.n_vencidos, 0)  AS prestamos_vencidos,
    COALESCE(p.n_tardias, 0)   AS devoluciones_tardias,
    COALESCE(m.n_pendientes, 0)     AS multas_pendientes,
    COALESCE(m.monto_pendiente, 0)  AS monto_pendiente
FROM usuarios u
LEFT JOIN (
    SELECT
        usuario_id,
        COUNT(*) AS n_total,
        COUNT(*) FILTER (WHERE fecha_devolucion IS NULL) AS n_activos,
        COUNT(*) FILTER (WHERE fecha_devolucion IS NULL
                           AND fecha_vencimiento < CURRENT_DATE) AS n_vencidos,
        COUNT(*) FILTER (WHERE fecha_devolucion > fecha_vencimiento) AS n_tardias
    FROM prestamos
    GROUP BY usuario_id
) p ON p.usuario_id = u.usuario_id
LEFT JOIN (
    SELECT
        pr.usuario_id,
        COUNT(*)      AS n_pendientes,
        SUM(mu.monto) AS monto_pendiente
    FROM multas mu
    JOIN prestamos pr ON pr.prestamo_id = mu.prestamo_id
    WHERE NOT mu.pagada
    GROUP BY pr.usuario_id
) m ON m.usuario_id = u.usuario_id;


-- -----------------------------------------------------
-- v_historial_usuario
-- Todos los préstamos de cada usuario con el libro, sus autores,
-- el estado, los días de retraso y la multa si la hubo.
-- Se usa para el perfil de cada usuario.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_historial_usuario AS
SELECT
    p.prestamo_id,
    p.usuario_id,
    l.libro_id,
    l.titulo,
    (
        SELECT string_agg(a.nombre || ' ' || a.apellido, ', ' ORDER BY a.apellido)
        FROM libros_autores la
        JOIN autores a ON a.autor_id = la.autor_id
        WHERE la.libro_id = l.libro_id
    ) AS autores,
    e.codigo_barras,
    p.fecha_prestamo,
    p.fecha_vencimiento,
    p.fecha_devolucion,
    CASE
        WHEN p.fecha_devolucion IS NULL AND p.fecha_vencimiento < CURRENT_DATE THEN 'Vencido'
        WHEN p.fecha_devolucion IS NULL THEN 'Activo'
        WHEN p.fecha_devolucion > p.fecha_vencimiento THEN 'Devuelto con retraso'
        ELSE 'Devuelto'
    END AS estado,
    CASE
        WHEN p.fecha_devolucion IS NULL
            THEN GREATEST(CURRENT_DATE - p.fecha_vencimiento, 0)
        ELSE GREATEST(p.fecha_devolucion - p.fecha_vencimiento, 0)
    END AS dias_retraso,
    m.monto  AS multa,
    m.pagada AS multa_pagada
FROM prestamos p
JOIN ejemplares e ON e.ejemplar_id = p.ejemplar_id
JOIN libros     l ON l.libro_id    = e.libro_id
LEFT JOIN multas m ON m.prestamo_id = p.prestamo_id;
