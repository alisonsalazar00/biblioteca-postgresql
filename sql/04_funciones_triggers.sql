-- =====================================================
-- Sistema de Biblioteca - Funciones y triggers
-- Se pueden ejecutar varias veces sin problema
-- (CREATE OR REPLACE actualiza lo que ya existe).
-- =====================================================


-- -----------------------------------------------------
-- prestar_libro(usuario, ejemplar, días)
-- Registra un préstamo si se cumplen las reglas de negocio:
--   RN-04: el plazo por defecto es de 14 días.
--   RN-05: solo los usuarios activos pueden pedir libros.
--   RN-06: solo un ejemplar 'disponible' puede prestarse.
-- Devuelve el id del préstamo creado. Si algo no se cumple,
-- lanza un error con un mensaje claro.
-- Uso: SELECT prestar_libro(1, 12);
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION prestar_libro(
    p_usuario_id  INT,
    p_ejemplar_id INT,
    p_dias        INT DEFAULT 14
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_activo      BOOLEAN;
    v_estado      VARCHAR(20);
    v_prestamo_id INT;
BEGIN
    -- 1. El usuario debe existir y estar activo
    SELECT activo INTO v_activo
    FROM usuarios
    WHERE usuario_id = p_usuario_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El usuario % no existe', p_usuario_id;
    END IF;

    IF NOT v_activo THEN
        RAISE EXCEPTION 'El usuario % está inactivo y no puede pedir libros', p_usuario_id;
    END IF;

    -- 2. El ejemplar debe existir y estar disponible
    --    FOR UPDATE bloquea la fila para que dos personas no
    --    presten la misma copia al mismo tiempo.
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

    -- 3. Se registra el préstamo
    INSERT INTO prestamos (ejemplar_id, usuario_id, fecha_prestamo, fecha_vencimiento)
    VALUES (p_ejemplar_id, p_usuario_id, CURRENT_DATE, CURRENT_DATE + p_dias)
    RETURNING prestamo_id INTO v_prestamo_id;

    RETURN v_prestamo_id;
END;
$$;


-- -----------------------------------------------------
-- devolver_libro(préstamo)
-- Marca el préstamo como devuelto hoy.
-- Devuelve los días de retraso (0 si se devolvió a tiempo).
-- Uso: SELECT devolver_libro(15);
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION devolver_libro(p_prestamo_id INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_vencimiento DATE;
    v_devolucion  DATE;
BEGIN
    SELECT fecha_vencimiento, fecha_devolucion
    INTO v_vencimiento, v_devolucion
    FROM prestamos
    WHERE prestamo_id = p_prestamo_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El préstamo % no existe', p_prestamo_id;
    END IF;

    IF v_devolucion IS NOT NULL THEN
        RAISE EXCEPTION 'El préstamo % ya fue devuelto el %', p_prestamo_id, v_devolucion;
    END IF;

    UPDATE prestamos
    SET fecha_devolucion = CURRENT_DATE
    WHERE prestamo_id = p_prestamo_id;

    RETURN GREATEST(CURRENT_DATE - v_vencimiento, 0);
END;
$$;


-- -----------------------------------------------------
-- Trigger: actualiza el estado del ejemplar (RN-09)
--   - Al crear un préstamo activo  -> el ejemplar pasa a 'prestado'.
--   - Al registrar la devolución   -> vuelve a 'disponible'.
-- Solo toca ejemplares en el estado esperado, así un ejemplar
-- 'perdido' o 'en_reparacion' no se marca disponible por error.
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
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prestamos_estado_ejemplar ON prestamos;

CREATE TRIGGER trg_prestamos_estado_ejemplar
AFTER INSERT OR UPDATE OF fecha_devolucion ON prestamos
FOR EACH ROW
EXECUTE FUNCTION actualizar_estado_ejemplar();
