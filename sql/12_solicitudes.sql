-- =====================================================
-- Sistema de Biblioteca - Solicitudes de préstamo
-- El cliente solicita un libro; el bibliotecario la aprueba
-- (y se registra el préstamo) o la rechaza.
-- Ejecutar DESPUÉS de 01 a 11.
-- Se puede ejecutar varias veces, pero recrea la tabla de
-- solicitudes: se pierden las solicitudes registradas.
-- =====================================================

DROP TABLE IF EXISTS solicitudes CASCADE;


-- -----------------------------------------------------
-- Solicitudes
-- Una solicitud es de un LIBRO, no de una copia concreta: al
-- aprobarla se elige la primera copia disponible.
-- El CHECK fija qué datos debe tener cada estado, así una solicitud
-- no puede quedar "aprobada" sin préstamo ni "rechazada" sin motivo.
-- -----------------------------------------------------
CREATE TABLE solicitudes (
    solicitud_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id       INT NOT NULL REFERENCES usuarios (usuario_id),
    libro_id         INT NOT NULL REFERENCES libros (libro_id),
    fecha_solicitud  TIMESTAMPTZ NOT NULL DEFAULT now(),
    estado           VARCHAR(20) NOT NULL DEFAULT 'pendiente'
                     CHECK (estado IN ('pendiente', 'aprobada', 'rechazada', 'cancelada')),
    fecha_resolucion TIMESTAMPTZ,
    resuelta_por     INT REFERENCES cuentas (cuenta_id),
    motivo_rechazo   TEXT,
    prestamo_id      INT UNIQUE REFERENCES prestamos (prestamo_id),
    CHECK (
        (estado = 'pendiente'
            AND fecha_resolucion IS NULL AND prestamo_id IS NULL)
        OR (estado = 'aprobada'
            AND fecha_resolucion IS NOT NULL AND prestamo_id IS NOT NULL)
        OR (estado = 'rechazada'
            AND fecha_resolucion IS NOT NULL AND prestamo_id IS NULL
            AND motivo_rechazo IS NOT NULL)
        OR (estado = 'cancelada'
            AND fecha_resolucion IS NOT NULL AND prestamo_id IS NULL)
    )
);

-- Una persona no puede tener dos solicitudes pendientes del mismo libro
CREATE UNIQUE INDEX uq_solicitud_pendiente
    ON solicitudes (usuario_id, libro_id)
    WHERE estado = 'pendiente';

CREATE INDEX idx_solicitudes_pendientes ON solicitudes (fecha_solicitud) WHERE estado = 'pendiente';
CREATE INDEX idx_solicitudes_usuario    ON solicitudes (usuario_id);

DROP TRIGGER IF EXISTS trg_auditoria_solicitudes ON solicitudes;
CREATE TRIGGER trg_auditoria_solicitudes
AFTER INSERT OR UPDATE OR DELETE ON solicitudes
FOR EACH ROW
EXECUTE FUNCTION registrar_auditoria('solicitud_id');


-- -----------------------------------------------------
-- cuenta_actual()
-- La cuenta que está actuando, según la variable que la aplicación
-- fija al inicio de cada transacción. NULL si no hay ninguna (por
-- ejemplo, alguien trabajando directamente en pgAdmin).
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION cuenta_actual()
RETURNS INT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_cuenta INT;
BEGIN
    v_cuenta := NULLIF(current_setting('biblioteca.cuenta_id', true), '')::INT;

    IF v_cuenta IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM cuentas WHERE cuenta_id = v_cuenta) THEN
        RETURN NULL;
    END IF;

    RETURN v_cuenta;
END;
$$;


-- -----------------------------------------------------
-- exigir_bibliotecario()
-- Lanza un error si la cuenta que actúa no es de un bibliotecario.
-- La base de datos comprueba el rol por su cuenta: no depende de que
-- la aplicación lo haya revisado antes.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION exigir_bibliotecario()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_cuenta INT;
    v_rol    VARCHAR(20);
BEGIN
    v_cuenta := cuenta_actual();

    IF v_cuenta IS NOT NULL THEN
        SELECT rol INTO v_rol FROM cuentas WHERE cuenta_id = v_cuenta;

        IF v_rol <> 'bibliotecario' THEN
            RAISE EXCEPTION 'Solo el bibliotecario puede hacer esta acción';
        END IF;
    END IF;
END;
$$;


-- -----------------------------------------------------
-- exigir_titular(usuario)
-- Lanza un error si la cuenta que actúa no es la del propio usuario.
-- Impide pedir o cancelar a nombre de otra persona.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION exigir_titular(p_usuario_id INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_cuenta INT;
BEGIN
    v_cuenta := cuenta_actual();

    IF v_cuenta IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM cuentas
           WHERE cuenta_id = v_cuenta AND usuario_id = p_usuario_id
       ) THEN
        RAISE EXCEPTION 'No puedes actuar a nombre de otra persona';
    END IF;
END;
$$;


-- -----------------------------------------------------
-- solicitar_prestamo(usuario, libro)
-- Reglas: usuario activo, sin multas pendientes, que no tenga ya el
-- libro, sin solicitud pendiente del mismo libro, máximo 3 solicitudes
-- pendientes, y que haya al menos una copia disponible.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION solicitar_prestamo(p_usuario_id INT, p_libro_id INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_activo         BOOLEAN;
    v_solicitud_id   INT;
    v_max_pendientes CONSTANT INT := 3;
BEGIN
    PERFORM exigir_titular(p_usuario_id);

    SELECT activo INTO v_activo FROM usuarios WHERE usuario_id = p_usuario_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El usuario % no existe', p_usuario_id;
    END IF;

    IF NOT v_activo THEN
        RAISE EXCEPTION 'El usuario % está inactivo y no puede pedir libros', p_usuario_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM libros WHERE libro_id = p_libro_id) THEN
        RAISE EXCEPTION 'El libro % no existe', p_libro_id;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM multas m
        JOIN prestamos p ON p.prestamo_id = m.prestamo_id
        WHERE p.usuario_id = p_usuario_id AND NOT m.pagada
    ) THEN
        RAISE EXCEPTION 'Tienes multas pendientes de pago. Págalas para poder solicitar libros';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM prestamos p
        JOIN ejemplares e ON e.ejemplar_id = p.ejemplar_id
        WHERE p.usuario_id = p_usuario_id
          AND p.fecha_devolucion IS NULL
          AND e.libro_id = p_libro_id
    ) THEN
        RAISE EXCEPTION 'Ya tienes prestado este libro';
    END IF;

    IF EXISTS (
        SELECT 1 FROM solicitudes
        WHERE usuario_id = p_usuario_id
          AND libro_id = p_libro_id
          AND estado = 'pendiente'
    ) THEN
        RAISE EXCEPTION 'Ya enviaste una solicitud para este libro';
    END IF;

    IF (SELECT COUNT(*) FROM solicitudes
        WHERE usuario_id = p_usuario_id AND estado = 'pendiente') >= v_max_pendientes THEN
        RAISE EXCEPTION 'Ya tienes % solicitudes pendientes. Espera a que las revisen o cancela alguna',
            v_max_pendientes;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM ejemplares WHERE libro_id = p_libro_id AND estado = 'disponible'
    ) THEN
        RAISE EXCEPTION 'No hay copias disponibles de este libro por ahora';
    END IF;

    INSERT INTO solicitudes (usuario_id, libro_id)
    VALUES (p_usuario_id, p_libro_id)
    RETURNING solicitud_id INTO v_solicitud_id;

    RETURN v_solicitud_id;
END;
$$;


-- -----------------------------------------------------
-- cancelar_solicitud(solicitud, usuario)
-- La persona cancela su propia solicitud mientras siga pendiente.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION cancelar_solicitud(p_solicitud_id INT, p_usuario_id INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_dueno  INT;
    v_estado VARCHAR(20);
BEGIN
    PERFORM exigir_titular(p_usuario_id);

    SELECT usuario_id, estado INTO v_dueno, v_estado
    FROM solicitudes
    WHERE solicitud_id = p_solicitud_id
    FOR UPDATE;

    -- Si la solicitud es de otra persona se responde igual que si no existiera
    IF NOT FOUND OR v_dueno <> p_usuario_id THEN
        RAISE EXCEPTION 'La solicitud % no existe', p_solicitud_id;
    END IF;

    IF v_estado <> 'pendiente' THEN
        RAISE EXCEPTION 'La solicitud ya no está pendiente';
    END IF;

    UPDATE solicitudes
    SET estado = 'cancelada',
        fecha_resolucion = now(),
        resuelta_por = cuenta_actual()
    WHERE solicitud_id = p_solicitud_id;
END;
$$;


-- -----------------------------------------------------
-- aprobar_solicitud(solicitud)
-- Solo el bibliotecario. Toma la primera copia disponible del libro
-- y registra el préstamo con prestar_libro, así se aplican TODAS las
-- reglas de siempre (usuario activo, sin multas, copia disponible).
-- Devuelve el id del préstamo creado.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION aprobar_solicitud(p_solicitud_id INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_solicitud solicitudes%ROWTYPE;
    v_ejemplar  INT;
    v_prestamo  INT;
BEGIN
    PERFORM exigir_bibliotecario();

    SELECT * INTO v_solicitud
    FROM solicitudes
    WHERE solicitud_id = p_solicitud_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La solicitud % no existe', p_solicitud_id;
    END IF;

    IF v_solicitud.estado <> 'pendiente' THEN
        RAISE EXCEPTION 'La solicitud ya fue resuelta (%)', v_solicitud.estado;
    END IF;

    SELECT ejemplar_id INTO v_ejemplar
    FROM ejemplares
    WHERE libro_id = v_solicitud.libro_id
      AND estado = 'disponible'
    ORDER BY codigo_barras
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay copias disponibles de este libro. Puedes rechazar la solicitud o esperar una devolución';
    END IF;

    v_prestamo := prestar_libro(v_solicitud.usuario_id, v_ejemplar);

    UPDATE solicitudes
    SET estado = 'aprobada',
        fecha_resolucion = now(),
        resuelta_por = cuenta_actual(),
        prestamo_id = v_prestamo
    WHERE solicitud_id = p_solicitud_id;

    RETURN v_prestamo;
END;
$$;


-- -----------------------------------------------------
-- rechazar_solicitud(solicitud, motivo)
-- Solo el bibliotecario, y con motivo obligatorio: la persona
-- puede leerlo en "Mis solicitudes".
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION rechazar_solicitud(p_solicitud_id INT, p_motivo TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado VARCHAR(20);
BEGIN
    PERFORM exigir_bibliotecario();

    IF btrim(COALESCE(p_motivo, '')) = '' THEN
        RAISE EXCEPTION 'Indica el motivo del rechazo';
    END IF;

    SELECT estado INTO v_estado
    FROM solicitudes
    WHERE solicitud_id = p_solicitud_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La solicitud % no existe', p_solicitud_id;
    END IF;

    IF v_estado <> 'pendiente' THEN
        RAISE EXCEPTION 'La solicitud ya fue resuelta (%)', v_estado;
    END IF;

    PERFORM set_config('biblioteca.motivo', btrim(p_motivo), true);

    UPDATE solicitudes
    SET estado = 'rechazada',
        fecha_resolucion = now(),
        resuelta_por = cuenta_actual(),
        motivo_rechazo = btrim(p_motivo)
    WHERE solicitud_id = p_solicitud_id;
END;
$$;


-- -----------------------------------------------------
-- v_solicitudes
-- Las solicitudes con la persona, el libro, quién las resolvió y
-- cuántas copias disponibles tiene hoy el libro (para saber si se
-- pueden aprobar).
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_solicitudes AS
SELECT
    s.solicitud_id,
    s.usuario_id,
    u.nombre || ' ' || u.apellido AS usuario,
    u.email,
    s.libro_id,
    l.titulo,
    (
        SELECT string_agg(a.nombre || ' ' || a.apellido, ', ' ORDER BY a.apellido)
        FROM libros_autores la
        JOIN autores a ON a.autor_id = la.autor_id
        WHERE la.libro_id = l.libro_id
    ) AS autores,
    s.fecha_solicitud,
    s.estado,
    s.fecha_resolucion,
    COALESCE(c.nombre_visible, ur.nombre || ' ' || ur.apellido) AS resuelta_por,
    s.motivo_rechazo,
    s.prestamo_id,
    (
        SELECT COUNT(*) FROM ejemplares e
        WHERE e.libro_id = s.libro_id AND e.estado = 'disponible'
    ) AS copias_disponibles
FROM solicitudes s
JOIN usuarios u ON u.usuario_id = s.usuario_id
JOIN libros   l ON l.libro_id   = s.libro_id
LEFT JOIN cuentas  c  ON c.cuenta_id   = s.resuelta_por
LEFT JOIN usuarios ur ON ur.usuario_id = c.usuario_id;


-- -----------------------------------------------------
-- v_auditoria actualizada (reemplaza la de 11)
-- Agrega los eventos de solicitudes. Mantiene las mismas columnas.
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
        WHEN a.tabla = 'solicitudes' AND a.operacion = 'INSERT'
            THEN 'Solicitud enviada'
        WHEN a.tabla = 'solicitudes' AND a.operacion = 'UPDATE'
             AND a.datos_nuevos ->> 'estado' = 'aprobada'
            THEN 'Solicitud aprobada'
        WHEN a.tabla = 'solicitudes' AND a.operacion = 'UPDATE'
             AND a.datos_nuevos ->> 'estado' = 'rechazada'
            THEN 'Solicitud rechazada'
        WHEN a.tabla = 'solicitudes' AND a.operacion = 'UPDATE'
             AND a.datos_nuevos ->> 'estado' = 'cancelada'
            THEN 'Solicitud cancelada'
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
LEFT JOIN cuentas     cta ON cta.cuenta_id  = a.cuenta_id
LEFT JOIN usuarios    uc  ON uc.usuario_id  = cta.usuario_id
LEFT JOIN multas      m   ON a.tabla = 'multas' AND m.multa_id = a.registro_id
LEFT JOIN solicitudes sol ON a.tabla = 'solicitudes' AND sol.solicitud_id = a.registro_id
LEFT JOIN prestamos   p   ON p.prestamo_id = CASE a.tabla
                                                 WHEN 'prestamos' THEN a.registro_id
                                                 WHEN 'multas'    THEN m.prestamo_id
                                             END
LEFT JOIN usuarios    u   ON u.usuario_id  = CASE a.tabla
                                                 WHEN 'usuarios'    THEN a.registro_id
                                                 WHEN 'solicitudes' THEN sol.usuario_id
                                                 ELSE p.usuario_id
                                             END
LEFT JOIN ejemplares  e   ON e.ejemplar_id  = p.ejemplar_id
LEFT JOIN libros      l   ON l.libro_id     = e.libro_id
LEFT JOIN ejemplares  ee  ON a.tabla = 'ejemplares' AND ee.ejemplar_id = a.registro_id
LEFT JOIN libros      lb  ON lb.libro_id    = CASE a.tabla
                                                  WHEN 'libros'       THEN a.registro_id
                                                  WHEN 'ejemplares'   THEN ee.libro_id
                                                  WHEN 'solicitudes'  THEN sol.libro_id
                                              END;
