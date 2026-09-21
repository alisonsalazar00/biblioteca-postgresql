-- =====================================================
-- Sistema de Biblioteca - Gestión del catálogo
-- Crear autores, categorías y libros; agregar copias;
-- cambiar el estado de un ejemplar.
-- Ejecutar DESPUÉS de 01 a 10.
-- Se puede ejecutar varias veces sin problema.
-- =====================================================


-- -----------------------------------------------------
-- Un mismo ISBN no puede registrarse dos veces aunque se escriba
-- distinto: 978-0-000-00001-1 y 9780000000011 son el mismo.
-- -----------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_libros_isbn_normalizado
    ON libros (upper(regexp_replace(isbn, '[^0-9Xx]', '', 'g')));


-- -----------------------------------------------------
-- auditar_manual(...)
-- Guarda un registro de auditoría a mano. Se usa cuando un cambio
-- no lo puede detectar el trigger de una sola tabla, como cambiar
-- los autores de un libro (que vive en la tabla libros_autores).
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION auditar_manual(
    p_tabla        TEXT,
    p_registro_id  INT,
    p_operacion    TEXT,
    p_anteriores   JSONB,
    p_nuevos       JSONB
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_cuenta_id INT;
    v_motivo    TEXT;
BEGIN
    v_motivo    := NULLIF(current_setting('biblioteca.motivo', true), '');
    v_cuenta_id := NULLIF(current_setting('biblioteca.cuenta_id', true), '')::INT;

    IF v_cuenta_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM cuentas WHERE cuenta_id = v_cuenta_id) THEN
        v_cuenta_id := NULL;
    END IF;

    INSERT INTO auditoria (tabla, registro_id, operacion,
                           datos_anteriores, datos_nuevos, motivo, cuenta_id)
    VALUES (p_tabla, p_registro_id, p_operacion,
            p_anteriores, p_nuevos, v_motivo, v_cuenta_id);
END;
$$;


-- -----------------------------------------------------
-- Tablas vigiladas por la auditoría
-- En ejemplares se registran las altas y bajas siempre, pero los
-- cambios de estado solo cuando los hace una persona (con la
-- variable biblioteca.cambio_manual). Así los cambios automáticos
-- de prestado/disponible que hace el trigger de préstamos no llenan
-- el historial de ruido.
-- -----------------------------------------------------
DROP TRIGGER IF EXISTS trg_auditoria_libros ON libros;
CREATE TRIGGER trg_auditoria_libros
AFTER INSERT OR UPDATE OR DELETE ON libros
FOR EACH ROW
EXECUTE FUNCTION registrar_auditoria('libro_id');

DROP TRIGGER IF EXISTS trg_auditoria_autores ON autores;
CREATE TRIGGER trg_auditoria_autores
AFTER INSERT OR UPDATE OR DELETE ON autores
FOR EACH ROW
EXECUTE FUNCTION registrar_auditoria('autor_id');

DROP TRIGGER IF EXISTS trg_auditoria_categorias ON categorias;
CREATE TRIGGER trg_auditoria_categorias
AFTER INSERT OR UPDATE OR DELETE ON categorias
FOR EACH ROW
EXECUTE FUNCTION registrar_auditoria('categoria_id');

DROP TRIGGER IF EXISTS trg_auditoria_ejemplares_alta ON ejemplares;
CREATE TRIGGER trg_auditoria_ejemplares_alta
AFTER INSERT OR DELETE ON ejemplares
FOR EACH ROW
EXECUTE FUNCTION registrar_auditoria('ejemplar_id');

DROP TRIGGER IF EXISTS trg_auditoria_ejemplares_estado ON ejemplares;
CREATE TRIGGER trg_auditoria_ejemplares_estado
AFTER UPDATE ON ejemplares
FOR EACH ROW
WHEN (current_setting('biblioteca.cambio_manual', true) = 'si')
EXECUTE FUNCTION registrar_auditoria('ejemplar_id');


-- -----------------------------------------------------
-- crear_categoria(nombre)
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION crear_categoria(p_nombre TEXT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id INT;
BEGIN
    IF btrim(COALESCE(p_nombre, '')) = '' THEN
        RAISE EXCEPTION 'El nombre de la categoría es obligatorio';
    END IF;

    IF EXISTS (SELECT 1 FROM categorias WHERE lower(nombre) = lower(btrim(p_nombre))) THEN
        RAISE EXCEPTION 'Ya existe la categoría %', btrim(p_nombre);
    END IF;

    INSERT INTO categorias (nombre) VALUES (btrim(p_nombre))
    RETURNING categoria_id INTO v_id;

    RETURN v_id;
END;
$$;


-- -----------------------------------------------------
-- crear_autor(nombre, apellido, nacionalidad, fecha de nacimiento)
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION crear_autor(
    p_nombre           TEXT,
    p_apellido         TEXT,
    p_nacionalidad     TEXT DEFAULT NULL,
    p_fecha_nacimiento DATE DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id INT;
BEGIN
    IF btrim(COALESCE(p_nombre, '')) = '' OR btrim(COALESCE(p_apellido, '')) = '' THEN
        RAISE EXCEPTION 'El nombre y el apellido del autor son obligatorios';
    END IF;

    IF p_fecha_nacimiento IS NOT NULL AND p_fecha_nacimiento > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede estar en el futuro';
    END IF;

    IF EXISTS (
        SELECT 1 FROM autores
        WHERE lower(nombre)   = lower(btrim(p_nombre))
          AND lower(apellido) = lower(btrim(p_apellido))
    ) THEN
        RAISE EXCEPTION 'Ya existe un autor llamado % %', btrim(p_nombre), btrim(p_apellido);
    END IF;

    INSERT INTO autores (nombre, apellido, nacionalidad, fecha_nacimiento)
    VALUES (btrim(p_nombre), btrim(p_apellido),
            NULLIF(btrim(COALESCE(p_nacionalidad, '')), ''),
            p_fecha_nacimiento)
    RETURNING autor_id INTO v_id;

    RETURN v_id;
END;
$$;


-- -----------------------------------------------------
-- validar_datos_libro(...)
-- Validaciones compartidas por crear_libro y editar_libro.
-- El ISBN debe tener 10 o 13 dígitos; se aceptan guiones y espacios.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION validar_datos_libro(
    p_isbn         TEXT,
    p_titulo       TEXT,
    p_anio         INT,
    p_categoria_id INT,
    p_autores      INT[]
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_isbn TEXT;
BEGIN
    IF btrim(COALESCE(p_titulo, '')) = '' THEN
        RAISE EXCEPTION 'El título es obligatorio';
    END IF;

    v_isbn := upper(regexp_replace(COALESCE(p_isbn, ''), '[^0-9Xx]', '', 'g'));
    IF v_isbn !~ '^([0-9]{9}[0-9X]|[0-9]{13})$' THEN
        RAISE EXCEPTION 'El ISBN debe tener 10 o 13 dígitos (se aceptan guiones)';
    END IF;

    IF p_anio IS NOT NULL
       AND (p_anio < 1000 OR p_anio > EXTRACT(YEAR FROM CURRENT_DATE)::INT + 1) THEN
        RAISE EXCEPTION 'El año de publicación no es válido';
    END IF;

    IF p_categoria_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM categorias WHERE categoria_id = p_categoria_id) THEN
        RAISE EXCEPTION 'Elige una categoría válida';
    END IF;

    IF COALESCE(array_length(p_autores, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Elige al menos un autor';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(p_autores) AS a(id)
        WHERE NOT EXISTS (SELECT 1 FROM autores WHERE autor_id = a.id)
    ) THEN
        RAISE EXCEPTION 'Alguno de los autores elegidos no existe';
    END IF;
END;
$$;


-- -----------------------------------------------------
-- agregar_ejemplares(libro, cantidad)
-- Agrega copias nuevas con códigos de barras consecutivos
-- (BIB-0025, BIB-0026...). El bloqueo asesor evita que dos personas
-- que agregan copias a la vez reciban el mismo código.
-- Devuelve cuántas copias agregó.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION agregar_ejemplares(p_libro_id INT, p_cantidad INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_ultimo INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM libros WHERE libro_id = p_libro_id) THEN
        RAISE EXCEPTION 'El libro % no existe', p_libro_id;
    END IF;

    IF p_cantidad IS NULL OR p_cantidad < 1 OR p_cantidad > 50 THEN
        RAISE EXCEPTION 'La cantidad de copias debe estar entre 1 y 50';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('codigos_ejemplares'));

    SELECT COALESCE(MAX(substring(codigo_barras FROM '^BIB-([0-9]+)$')::INT), 0)
    INTO v_ultimo
    FROM ejemplares;

    INSERT INTO ejemplares (libro_id, codigo_barras)
    SELECT p_libro_id, 'BIB-' || lpad((v_ultimo + n)::TEXT, 4, '0')
    FROM generate_series(1, p_cantidad) AS n;

    RETURN p_cantidad;
END;
$$;


-- -----------------------------------------------------
-- crear_libro(isbn, título, año, categoría, autores, copias)
-- Crea el libro, lo une a sus autores y agrega sus copias iniciales,
-- todo en una sola transacción. Devuelve el id del libro.
-- Uso: SELECT crear_libro('9780000000123', 'Título', 2020, 1, ARRAY[1,2], 2);
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION crear_libro(
    p_isbn         TEXT,
    p_titulo       TEXT,
    p_anio         INT,
    p_categoria_id INT,
    p_autores      INT[],
    p_copias       INT DEFAULT 1
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_libro_id INT;
BEGIN
    PERFORM validar_datos_libro(p_isbn, p_titulo, p_anio, p_categoria_id, p_autores);

    IF p_copias IS NULL OR p_copias < 0 OR p_copias > 50 THEN
        RAISE EXCEPTION 'Las copias iniciales deben estar entre 0 y 50';
    END IF;

    IF EXISTS (
        SELECT 1 FROM libros
        WHERE upper(regexp_replace(isbn, '[^0-9Xx]', '', 'g'))
            = upper(regexp_replace(p_isbn, '[^0-9Xx]', '', 'g'))
    ) THEN
        RAISE EXCEPTION 'Ya existe un libro con el ISBN %', btrim(p_isbn);
    END IF;

    INSERT INTO libros (isbn, titulo, anio_publicacion, categoria_id)
    VALUES (btrim(p_isbn), btrim(p_titulo), p_anio, p_categoria_id)
    RETURNING libro_id INTO v_libro_id;

    INSERT INTO libros_autores (libro_id, autor_id)
    SELECT DISTINCT v_libro_id, id FROM unnest(p_autores) AS a(id);

    IF p_copias > 0 THEN
        PERFORM agregar_ejemplares(v_libro_id, p_copias);
    END IF;

    RETURN v_libro_id;
END;
$$;


-- -----------------------------------------------------
-- editar_libro(libro, isbn, título, año, categoría, autores)
-- Si cambian los autores, el cambio se anota en la auditoría a mano
-- (auditar_manual), porque el trigger de libros no lo ve.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION editar_libro(
    p_libro_id     INT,
    p_isbn         TEXT,
    p_titulo       TEXT,
    p_anio         INT,
    p_categoria_id INT,
    p_autores      INT[]
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_autores_antes   JSONB;
    v_autores_despues JSONB;
    v_cambiaron       BOOLEAN;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM libros WHERE libro_id = p_libro_id FOR UPDATE) THEN
        RAISE EXCEPTION 'El libro % no existe', p_libro_id;
    END IF;

    PERFORM validar_datos_libro(p_isbn, p_titulo, p_anio, p_categoria_id, p_autores);

    IF EXISTS (
        SELECT 1 FROM libros
        WHERE libro_id <> p_libro_id
          AND upper(regexp_replace(isbn, '[^0-9Xx]', '', 'g'))
            = upper(regexp_replace(p_isbn, '[^0-9Xx]', '', 'g'))
    ) THEN
        RAISE EXCEPTION 'Ya existe otro libro con el ISBN %', btrim(p_isbn);
    END IF;

    -- ¿Cambiaron los autores? Se comparan los conjuntos de ids.
    v_cambiaron := (
        SELECT array_agg(autor_id ORDER BY autor_id)
        FROM libros_autores WHERE libro_id = p_libro_id
    ) IS DISTINCT FROM (
        SELECT array_agg(DISTINCT id ORDER BY id) FROM unnest(p_autores) AS a(id)
    );

    SELECT jsonb_agg(a.nombre || ' ' || a.apellido ORDER BY a.apellido, a.nombre)
    INTO v_autores_antes
    FROM libros_autores la
    JOIN autores a ON a.autor_id = la.autor_id
    WHERE la.libro_id = p_libro_id;

    UPDATE libros
    SET isbn             = btrim(p_isbn),
        titulo           = btrim(p_titulo),
        anio_publicacion = p_anio,
        categoria_id     = p_categoria_id
    WHERE libro_id = p_libro_id;

    IF v_cambiaron THEN
        DELETE FROM libros_autores
        WHERE libro_id = p_libro_id
          AND autor_id <> ALL (p_autores);

        INSERT INTO libros_autores (libro_id, autor_id)
        SELECT DISTINCT p_libro_id, id FROM unnest(p_autores) AS a(id)
        ON CONFLICT DO NOTHING;

        SELECT jsonb_agg(a.nombre || ' ' || a.apellido ORDER BY a.apellido, a.nombre)
        INTO v_autores_despues
        FROM libros_autores la
        JOIN autores a ON a.autor_id = la.autor_id
        WHERE la.libro_id = p_libro_id;

        PERFORM auditar_manual('libros', p_libro_id, 'UPDATE',
                               jsonb_build_object('autores', v_autores_antes),
                               jsonb_build_object('autores', v_autores_despues));
    END IF;
END;
$$;


-- -----------------------------------------------------
-- cambiar_estado_ejemplar(ejemplar, estado, motivo)
-- Para marcar una copia como en reparación o perdida, o volver a
-- dejarla disponible. El estado 'prestado' no se puede poner a mano:
-- lo maneja el préstamo. Una copia prestada no se puede tocar hasta
-- que se devuelva. Exige motivo.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION cambiar_estado_ejemplar(
    p_ejemplar_id INT,
    p_estado      TEXT,
    p_motivo      TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_actual VARCHAR(20);
BEGIN
    IF p_estado IS NULL OR p_estado NOT IN ('disponible', 'en_reparacion', 'perdido') THEN
        RAISE EXCEPTION 'El estado debe ser disponible, en_reparacion o perdido';
    END IF;

    IF btrim(COALESCE(p_motivo, '')) = '' THEN
        RAISE EXCEPTION 'Indica el motivo del cambio de estado';
    END IF;

    SELECT estado INTO v_actual
    FROM ejemplares
    WHERE ejemplar_id = p_ejemplar_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El ejemplar % no existe', p_ejemplar_id;
    END IF;

    IF v_actual = 'prestado' THEN
        RAISE EXCEPTION 'El ejemplar está prestado. Registra primero la devolución';
    END IF;

    IF v_actual = p_estado THEN
        RAISE EXCEPTION 'El ejemplar ya está en ese estado';
    END IF;

    PERFORM set_config('biblioteca.motivo', btrim(p_motivo), true);
    PERFORM set_config('biblioteca.cambio_manual', 'si', true);

    UPDATE ejemplares
    SET estado = p_estado
    WHERE ejemplar_id = p_ejemplar_id;
END;
$$;


-- -----------------------------------------------------
-- v_auditoria actualizada (reemplaza la de 09)
-- Agrega los eventos del catálogo y resuelve el libro afectado
-- también para libros y ejemplares. Mantiene las mismas columnas.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_auditoria AS
SELECT
    a.auditoria_id,
    a.fecha_hora,
    a.tabla,
    a.registro_id,
    a.operacion,
    CASE
        WHEN a.tabla = 'prestamos' AND a.operacion = 'INSERT'
            THEN 'Préstamo registrado'
        WHEN a.tabla = 'prestamos' AND a.operacion = 'UPDATE'
             AND a.datos_nuevos ? 'fecha_devolucion'
            THEN 'Devolución registrada'
        WHEN a.tabla = 'prestamos' AND a.operacion = 'UPDATE'
            THEN 'Préstamo corregido'
        WHEN a.tabla = 'prestamos' AND a.operacion = 'DELETE'
            THEN 'Préstamo eliminado'
        WHEN a.tabla = 'multas' AND a.operacion = 'INSERT'
            THEN 'Multa generada'
        WHEN a.tabla = 'multas' AND a.operacion = 'UPDATE'
             AND (a.datos_nuevos ->> 'pagada')::BOOLEAN
            THEN 'Multa pagada'
        WHEN a.tabla = 'multas' AND a.operacion = 'UPDATE'
             AND a.datos_nuevos ? 'pagada'
            THEN 'Pago de multa anulado'
        WHEN a.tabla = 'usuarios' AND a.operacion = 'INSERT'
            THEN 'Usuario creado'
        WHEN a.tabla = 'usuarios' AND a.operacion = 'UPDATE'
             AND a.datos_nuevos ? 'activo'
             AND (a.datos_nuevos ->> 'activo')::BOOLEAN
            THEN 'Usuario activado'
        WHEN a.tabla = 'usuarios' AND a.operacion = 'UPDATE'
             AND a.datos_nuevos ? 'activo'
            THEN 'Usuario desactivado'
        WHEN a.tabla = 'usuarios' AND a.operacion = 'UPDATE'
            THEN 'Usuario editado'
        WHEN a.tabla = 'libros' AND a.operacion = 'INSERT'
            THEN 'Libro creado'
        WHEN a.tabla = 'libros' AND a.operacion = 'UPDATE'
            THEN 'Libro editado'
        WHEN a.tabla = 'libros' AND a.operacion = 'DELETE'
            THEN 'Libro eliminado'
        WHEN a.tabla = 'autores' AND a.operacion = 'INSERT'
            THEN 'Autor creado'
        WHEN a.tabla = 'autores' AND a.operacion = 'UPDATE'
            THEN 'Autor editado'
        WHEN a.tabla = 'categorias' AND a.operacion = 'INSERT'
            THEN 'Categoría creada'
        WHEN a.tabla = 'categorias' AND a.operacion = 'UPDATE'
            THEN 'Categoría editada'
        WHEN a.tabla = 'ejemplares' AND a.operacion = 'INSERT'
            THEN 'Ejemplar agregado'
        WHEN a.tabla = 'ejemplares' AND a.operacion = 'UPDATE'
            THEN 'Estado de ejemplar cambiado'
        WHEN a.tabla = 'ejemplares' AND a.operacion = 'DELETE'
            THEN 'Ejemplar eliminado'
        ELSE a.operacion || ' en ' || a.tabla
    END AS evento,
    a.cuenta_id,
    COALESCE(cta.nombre_visible,
             uc.nombre || ' ' || uc.apellido,
             'Acceso directo a la base de datos') AS responsable,
    u.nombre || ' ' || u.apellido AS usuario,
    COALESCE(l.titulo, lb.titulo) AS libro,
    (SELECT us.nombre || ' ' || us.apellido
     FROM usuarios us
     WHERE us.usuario_id = (a.datos_anteriores ->> 'usuario_id')::INT
       AND a.tabla = 'prestamos') AS usuario_anterior,
    (SELECT us.nombre || ' ' || us.apellido
     FROM usuarios us
     WHERE us.usuario_id = (a.datos_nuevos ->> 'usuario_id')::INT
       AND a.tabla = 'prestamos') AS usuario_nuevo,
    (SELECT ex.codigo_barras || ' - ' || lx.titulo
     FROM ejemplares ex
     JOIN libros lx ON lx.libro_id = ex.libro_id
     WHERE ex.ejemplar_id = (a.datos_anteriores ->> 'ejemplar_id')::INT
       AND a.tabla = 'prestamos') AS ejemplar_anterior,
    (SELECT ex.codigo_barras || ' - ' || lx.titulo
     FROM ejemplares ex
     JOIN libros lx ON lx.libro_id = ex.libro_id
     WHERE ex.ejemplar_id = (a.datos_nuevos ->> 'ejemplar_id')::INT
       AND a.tabla = 'prestamos') AS ejemplar_nuevo,
    a.datos_anteriores,
    a.datos_nuevos,
    a.motivo,
    a.usuario_bd
FROM auditoria a
LEFT JOIN cuentas    cta ON cta.cuenta_id  = a.cuenta_id
LEFT JOIN usuarios   uc  ON uc.usuario_id  = cta.usuario_id
LEFT JOIN multas     m   ON a.tabla = 'multas' AND m.multa_id = a.registro_id
LEFT JOIN prestamos  p   ON p.prestamo_id = CASE a.tabla
                                                WHEN 'prestamos' THEN a.registro_id
                                                WHEN 'multas'    THEN m.prestamo_id
                                            END
LEFT JOIN usuarios   u   ON u.usuario_id  = CASE a.tabla
                                                WHEN 'usuarios' THEN a.registro_id
                                                ELSE p.usuario_id
                                            END
LEFT JOIN ejemplares e   ON e.ejemplar_id  = p.ejemplar_id
LEFT JOIN libros     l   ON l.libro_id     = e.libro_id
LEFT JOIN ejemplares ee  ON a.tabla = 'ejemplares' AND ee.ejemplar_id = a.registro_id
LEFT JOIN libros     lb  ON lb.libro_id    = CASE a.tabla
                                                 WHEN 'libros'     THEN a.registro_id
                                                 WHEN 'ejemplares' THEN ee.libro_id
                                             END;
