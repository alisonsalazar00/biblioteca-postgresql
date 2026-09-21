-- =====================================================
-- Sistema de Biblioteca - Auditoría y correcciones
-- Ejecutar DESPUÉS de 01 a 08.
-- Se puede ejecutar varias veces, pero recrea la tabla de
-- auditoría, así que se pierde el historial registrado.
-- =====================================================

DROP TABLE IF EXISTS auditoria CASCADE;


-- -----------------------------------------------------
-- Tabla de auditoría
-- Guarda un registro por cada cambio en las tablas vigiladas:
-- qué cambió, cuándo, por qué y QUIÉN lo hizo.
-- Los datos se guardan como JSONB, así una sola tabla sirve
-- para auditar cualquier otra sin importar sus columnas.
-- En un UPDATE solo se guardan las columnas que cambiaron.
-- -----------------------------------------------------
CREATE TABLE auditoria (
    auditoria_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_hora       TIMESTAMPTZ NOT NULL DEFAULT now(),
    tabla            VARCHAR(50) NOT NULL,
    registro_id      INT NOT NULL,
    operacion        VARCHAR(10) NOT NULL
                     CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
    datos_anteriores JSONB,
    datos_nuevos     JSONB,
    motivo           TEXT,
    cuenta_id        INT REFERENCES cuentas (cuenta_id),
    usuario_bd       VARCHAR(63) NOT NULL DEFAULT current_user
);

CREATE INDEX idx_auditoria_registro ON auditoria (tabla, registro_id);
CREATE INDEX idx_auditoria_fecha    ON auditoria (fecha_hora DESC);
CREATE INDEX idx_auditoria_cuenta   ON auditoria (cuenta_id);


-- -----------------------------------------------------
-- El historial es de solo escritura: no se puede modificar
-- ni borrar ninguna fila, ni vaciar la tabla. Así nadie puede
-- "limpiar" el rastro de un cambio.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION bloquear_cambios_auditoria()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'El historial de auditoría no se puede modificar ni borrar';
END;
$$;

CREATE TRIGGER trg_auditoria_inmutable
BEFORE UPDATE OR DELETE ON auditoria
FOR EACH ROW
EXECUTE FUNCTION bloquear_cambios_auditoria();

CREATE TRIGGER trg_auditoria_sin_truncate
BEFORE TRUNCATE ON auditoria
FOR EACH STATEMENT
EXECUTE FUNCTION bloquear_cambios_auditoria();


-- -----------------------------------------------------
-- Trigger genérico de auditoría
-- Se le pasa como argumento el nombre de la llave primaria
-- de la tabla vigilada (por ejemplo 'prestamo_id').
--
-- Dos datos viajan desde la aplicación o desde las funciones
-- mediante variables que solo viven durante la transacción:
--   biblioteca.cuenta_id  la cuenta que hace el cambio
--   biblioteca.motivo     la razón de una corrección
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION registrar_auditoria()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_anterior           JSONB;
    v_nuevo              JSONB;
    v_cambios_anteriores JSONB;
    v_cambios_nuevos     JSONB;
    v_motivo             TEXT;
    v_cuenta_id          INT;
BEGIN
    v_motivo    := NULLIF(current_setting('biblioteca.motivo', true), '');
    v_cuenta_id := NULLIF(current_setting('biblioteca.cuenta_id', true), '')::INT;

    -- Si la cuenta ya no existe (por ejemplo, una sesión vieja), el cambio
    -- se registra sin responsable en vez de fallar.
    IF v_cuenta_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM cuentas WHERE cuenta_id = v_cuenta_id) THEN
        v_cuenta_id := NULL;
    END IF;

    IF TG_OP = 'INSERT' THEN
        v_nuevo := to_jsonb(NEW);

        INSERT INTO auditoria (tabla, registro_id, operacion, datos_nuevos, motivo, cuenta_id)
        VALUES (TG_TABLE_NAME, (v_nuevo ->> TG_ARGV[0])::INT, 'INSERT',
                v_nuevo, v_motivo, v_cuenta_id);

        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        v_anterior := to_jsonb(OLD);
        v_nuevo    := to_jsonb(NEW);

        -- Si no cambió ningún valor, no hay nada que registrar
        IF v_anterior = v_nuevo THEN
            RETURN NEW;
        END IF;

        -- Se guardan únicamente las columnas que cambiaron
        SELECT jsonb_object_agg(n.key, v_anterior -> n.key),
               jsonb_object_agg(n.key, n.value)
        INTO v_cambios_anteriores, v_cambios_nuevos
        FROM jsonb_each(v_nuevo) AS n
        WHERE v_anterior -> n.key IS DISTINCT FROM n.value;

        INSERT INTO auditoria (tabla, registro_id, operacion,
                               datos_anteriores, datos_nuevos, motivo, cuenta_id)
        VALUES (TG_TABLE_NAME, (v_nuevo ->> TG_ARGV[0])::INT, 'UPDATE',
                v_cambios_anteriores, v_cambios_nuevos, v_motivo, v_cuenta_id);

        RETURN NEW;

    ELSE
        v_anterior := to_jsonb(OLD);

        INSERT INTO auditoria (tabla, registro_id, operacion, datos_anteriores, motivo, cuenta_id)
        VALUES (TG_TABLE_NAME, (v_anterior ->> TG_ARGV[0])::INT, 'DELETE',
                v_anterior, v_motivo, v_cuenta_id);

        RETURN OLD;
    END IF;
END;
$$;


-- -----------------------------------------------------
-- Tablas vigiladas: préstamos, multas y usuarios
-- La tabla de cuentas NO se audita con este trigger a propósito:
-- copiaría el hash de las contraseñas dentro del historial.
-- -----------------------------------------------------
DROP TRIGGER IF EXISTS trg_auditoria_prestamos ON prestamos;

CREATE TRIGGER trg_auditoria_prestamos
AFTER INSERT OR UPDATE OR DELETE ON prestamos
FOR EACH ROW
EXECUTE FUNCTION registrar_auditoria('prestamo_id');

DROP TRIGGER IF EXISTS trg_auditoria_multas ON multas;

CREATE TRIGGER trg_auditoria_multas
AFTER INSERT OR UPDATE OR DELETE ON multas
FOR EACH ROW
EXECUTE FUNCTION registrar_auditoria('multa_id');

DROP TRIGGER IF EXISTS trg_auditoria_usuarios ON usuarios;

CREATE TRIGGER trg_auditoria_usuarios
AFTER INSERT OR UPDATE OR DELETE ON usuarios
FOR EACH ROW
EXECUTE FUNCTION registrar_auditoria('usuario_id');


-- -----------------------------------------------------
-- Trigger de estado del ejemplar, actualizado
-- (reemplaza la versión de 05). Ahora también cubre el caso
-- en que se corrige el ejemplar de un préstamo activo:
-- el ejemplar equivocado queda 'disponible' y el correcto
-- pasa a 'prestado'.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION actualizar_estado_ejemplar()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.fecha_devolucion IS NULL THEN
        UPDATE ejemplares
        SET estado = 'prestado'
        WHERE ejemplar_id = NEW.ejemplar_id
          AND estado = 'disponible';

    ELSIF TG_OP = 'UPDATE'
          AND OLD.fecha_devolucion IS NULL
          AND NEW.fecha_devolucion IS NOT NULL THEN
        UPDATE ejemplares
        SET estado = 'disponible'
        WHERE ejemplar_id = NEW.ejemplar_id
          AND estado = 'prestado';

    ELSIF TG_OP = 'UPDATE'
          AND OLD.fecha_devolucion IS NULL
          AND NEW.fecha_devolucion IS NULL
          AND OLD.ejemplar_id <> NEW.ejemplar_id THEN
        UPDATE ejemplares
        SET estado = 'disponible'
        WHERE ejemplar_id = OLD.ejemplar_id
          AND estado = 'prestado';

        UPDATE ejemplares
        SET estado = 'prestado'
        WHERE ejemplar_id = NEW.ejemplar_id
          AND estado = 'disponible';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prestamos_estado_ejemplar ON prestamos;

CREATE TRIGGER trg_prestamos_estado_ejemplar
AFTER INSERT OR UPDATE OF fecha_devolucion, ejemplar_id ON prestamos
FOR EACH ROW
EXECUTE FUNCTION actualizar_estado_ejemplar();


-- -----------------------------------------------------
-- corregir_prestamo(préstamo, usuario, ejemplar, motivo)
-- Cambia el usuario o el ejemplar de un préstamo ACTIVO.
-- Aplica las mismas reglas que prestar_libro y exige un motivo.
-- Las fechas del préstamo no cambian.
-- Uso: SELECT corregir_prestamo(20, 3, 12, 'Se registró a otra persona');
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION corregir_prestamo(
    p_prestamo_id INT,
    p_usuario_id  INT,
    p_ejemplar_id INT,
    p_motivo      TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_usuario_actual  INT;
    v_ejemplar_actual INT;
    v_devolucion      DATE;
    v_activo          BOOLEAN;
    v_estado          VARCHAR(20);
BEGIN
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'Indica el motivo de la corrección';
    END IF;

    SELECT usuario_id, ejemplar_id, fecha_devolucion
    INTO v_usuario_actual, v_ejemplar_actual, v_devolucion
    FROM prestamos
    WHERE prestamo_id = p_prestamo_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El préstamo % no existe', p_prestamo_id;
    END IF;

    IF v_devolucion IS NOT NULL THEN
        RAISE EXCEPTION 'El préstamo % ya fue devuelto y no se puede corregir', p_prestamo_id;
    END IF;

    IF p_usuario_id = v_usuario_actual AND p_ejemplar_id = v_ejemplar_actual THEN
        RAISE EXCEPTION 'No hay nada que corregir: el usuario y el ejemplar son los mismos';
    END IF;

    -- Si cambia el usuario, debe cumplir las reglas para pedir libros
    IF p_usuario_id <> v_usuario_actual THEN
        SELECT activo INTO v_activo
        FROM usuarios
        WHERE usuario_id = p_usuario_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'El usuario % no existe', p_usuario_id;
        END IF;

        IF NOT v_activo THEN
            RAISE EXCEPTION 'El usuario % está inactivo y no puede pedir libros', p_usuario_id;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM multas m
            JOIN prestamos p ON p.prestamo_id = m.prestamo_id
            WHERE p.usuario_id = p_usuario_id
              AND NOT m.pagada
        ) THEN
            RAISE EXCEPTION 'El usuario % tiene multas pendientes de pago', p_usuario_id;
        END IF;
    END IF;

    -- Si cambia el ejemplar, el nuevo debe estar disponible
    IF p_ejemplar_id <> v_ejemplar_actual THEN
        SELECT estado INTO v_estado
        FROM ejemplares
        WHERE ejemplar_id = p_ejemplar_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'El ejemplar % no existe', p_ejemplar_id;
        END IF;

        IF v_estado <> 'disponible' THEN
            RAISE EXCEPTION 'El ejemplar % no está disponible (estado actual: %)',
                p_ejemplar_id, v_estado;
        END IF;
    END IF;

    -- El motivo viaja al trigger de auditoría (solo dura esta transacción)
    PERFORM set_config('biblioteca.motivo', btrim(p_motivo), true);

    UPDATE prestamos
    SET usuario_id  = p_usuario_id,
        ejemplar_id = p_ejemplar_id
    WHERE prestamo_id = p_prestamo_id;
END;
$$;


-- -----------------------------------------------------
-- anular_pago_multa(multa, motivo)
-- Deja pendiente una multa que se marcó como pagada por error.
-- Uso: SELECT anular_pago_multa(1, 'El pago se registró por error');
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION anular_pago_multa(
    p_multa_id INT,
    p_motivo   TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_pagada BOOLEAN;
BEGIN
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'Indica el motivo para anular el pago';
    END IF;

    SELECT pagada INTO v_pagada
    FROM multas
    WHERE multa_id = p_multa_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La multa % no existe', p_multa_id;
    END IF;

    IF NOT v_pagada THEN
        RAISE EXCEPTION 'La multa % no está pagada, no hay un pago que anular', p_multa_id;
    END IF;

    PERFORM set_config('biblioteca.motivo', btrim(p_motivo), true);

    UPDATE multas
    SET pagada = FALSE,
        fecha_pago = NULL
    WHERE multa_id = p_multa_id;
END;
$$;


-- -----------------------------------------------------
-- v_auditoria
-- El historial listo para mostrar: un nombre legible para cada
-- evento, la cuenta responsable, y los ids resueltos a nombres
-- (usuario, ejemplar, libro) para que se entienda sin buscar en
-- otras tablas. El operador ? de JSONB pregunta si una clave existe.
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
        ELSE a.operacion || ' en ' || a.tabla
    END AS evento,
    a.cuenta_id,
    COALESCE(cta.nombre_visible,
             uc.nombre || ' ' || uc.apellido,
             'Acceso directo a la base de datos') AS responsable,
    -- Usuario y libro afectados (según su estado actual)
    u.nombre || ' ' || u.apellido AS usuario,
    l.titulo AS libro,
    -- Solo tienen valor cuando el cambio tocó el usuario o el ejemplar
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
     WHERE ex.ejemplar_id = (a.datos_anteriores ->> 'ejemplar_id')::INT) AS ejemplar_anterior,
    (SELECT ex.codigo_barras || ' - ' || lx.titulo
     FROM ejemplares ex
     JOIN libros lx ON lx.libro_id = ex.libro_id
     WHERE ex.ejemplar_id = (a.datos_nuevos ->> 'ejemplar_id')::INT) AS ejemplar_nuevo,
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
LEFT JOIN libros     l   ON l.libro_id     = e.libro_id;
