-- =====================================================
-- Sistema de Biblioteca - Multas por retraso
-- Se puede ejecutar varias veces: recrea la tabla de
-- multas y vuelve a calcular las de los préstamos
-- ya devueltos con retraso (se pierden los pagos hechos).
-- Ejecutar DESPUÉS de 01 a 05.
-- =====================================================

DROP TABLE IF EXISTS multas CASCADE;


-- -----------------------------------------------------
-- Parámetros del sistema
-- Guardar la tarifa en una tabla evita dejarla escrita
-- dentro del código: se cambia con un UPDATE.
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS parametros (
    clave       VARCHAR(50) PRIMARY KEY,
    valor       NUMERIC(10, 2) NOT NULL CHECK (valor >= 0),
    descripcion VARCHAR(200)
);

INSERT INTO parametros (clave, valor, descripcion) VALUES
    ('multa_por_dia', 100, 'Monto de la multa en colones por cada día de retraso')
ON CONFLICT (clave) DO NOTHING;


-- -----------------------------------------------------
-- Multas
-- Cada préstamo devuelto con retraso genera, como máximo,
-- una multa (UNIQUE en prestamo_id).
-- El CHECK final obliga a que una multa pagada tenga fecha
-- de pago y una pendiente no la tenga.
-- -----------------------------------------------------
CREATE TABLE multas (
    multa_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    prestamo_id    INT NOT NULL UNIQUE REFERENCES prestamos (prestamo_id),
    dias_retraso   INT NOT NULL CHECK (dias_retraso > 0),
    monto          NUMERIC(10, 2) NOT NULL CHECK (monto >= 0),
    fecha_generada DATE NOT NULL DEFAULT CURRENT_DATE,
    pagada         BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_pago     DATE,
    CHECK (
        (pagada AND fecha_pago IS NOT NULL)
        OR (NOT pagada AND fecha_pago IS NULL)
    )
);

-- Índice parcial: solo indexa las multas pendientes,
-- que son las que se consultan más seguido.
CREATE INDEX idx_multas_pendientes ON multas (pagada) WHERE NOT pagada;


-- -----------------------------------------------------
-- calcular_multa(días de retraso)
-- Devuelve el monto según la tarifa guardada en parametros.
-- Uso: SELECT calcular_multa(5);
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_multa(p_dias_retraso INT)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    SELECT GREATEST(p_dias_retraso, 0) * valor
    FROM parametros
    WHERE clave = 'multa_por_dia';
$$;


-- -----------------------------------------------------
-- Trigger: genera la multa al devolver un libro tarde
-- La cláusula WHEN hace que solo se ejecute cuando el
-- préstamo pasa de "sin devolver" a "devuelto".
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION generar_multa()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_dias INT;
BEGIN
    v_dias := NEW.fecha_devolucion - NEW.fecha_vencimiento;

    IF v_dias > 0 THEN
        INSERT INTO multas (prestamo_id, dias_retraso, monto)
        VALUES (NEW.prestamo_id, v_dias, calcular_multa(v_dias));
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prestamos_generar_multa ON prestamos;

CREATE TRIGGER trg_prestamos_generar_multa
AFTER UPDATE OF fecha_devolucion ON prestamos
FOR EACH ROW
WHEN (OLD.fecha_devolucion IS NULL AND NEW.fecha_devolucion IS NOT NULL)
EXECUTE FUNCTION generar_multa();


-- -----------------------------------------------------
-- pagar_multa(multa)
-- Marca la multa como pagada hoy y devuelve el monto.
-- Uso: SELECT pagar_multa(1);
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION pagar_multa(p_multa_id INT)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_pagada BOOLEAN;
    v_monto  NUMERIC;
BEGIN
    SELECT pagada, monto INTO v_pagada, v_monto
    FROM multas
    WHERE multa_id = p_multa_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La multa % no existe', p_multa_id;
    END IF;

    IF v_pagada THEN
        RAISE EXCEPTION 'La multa % ya fue pagada', p_multa_id;
    END IF;

    UPDATE multas
    SET pagada = TRUE,
        fecha_pago = CURRENT_DATE
    WHERE multa_id = p_multa_id;

    RETURN v_monto;
END;
$$;


-- -----------------------------------------------------
-- prestar_libro actualizada (reemplaza la versión de 05)
-- Regla nueva: un usuario con multas pendientes no puede
-- pedir libros hasta pagarlas.
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

    -- 2. No debe tener multas pendientes
    IF EXISTS (
        SELECT 1
        FROM multas m
        JOIN prestamos p ON p.prestamo_id = m.prestamo_id
        WHERE p.usuario_id = p_usuario_id
          AND NOT m.pagada
    ) THEN
        RAISE EXCEPTION 'El usuario % tiene multas pendientes de pago', p_usuario_id;
    END IF;

    -- 3. El ejemplar debe existir y estar disponible
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

    -- 4. Se registra el préstamo
    INSERT INTO prestamos (ejemplar_id, usuario_id, fecha_prestamo, fecha_vencimiento)
    VALUES (p_ejemplar_id, p_usuario_id, CURRENT_DATE, CURRENT_DATE + p_dias)
    RETURNING prestamo_id INTO v_prestamo_id;

    RETURN v_prestamo_id;
END;
$$;


-- -----------------------------------------------------
-- v_multas
-- Multas con el usuario y el libro ya unidos, para la interfaz.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_multas AS
SELECT
    m.multa_id,
    u.usuario_id,
    u.nombre || ' ' || u.apellido AS usuario,
    u.email,
    l.titulo,
    m.dias_retraso,
    m.monto,
    m.fecha_generada,
    m.pagada,
    m.fecha_pago
FROM multas m
JOIN prestamos  p ON p.prestamo_id = m.prestamo_id
JOIN usuarios   u ON u.usuario_id  = p.usuario_id
JOIN ejemplares e ON e.ejemplar_id = p.ejemplar_id
JOIN libros     l ON l.libro_id    = e.libro_id;


-- -----------------------------------------------------
-- Multas de los préstamos que ya se habían devuelto tarde
-- (los datos de prueba se cargaron antes de que existiera
-- el trigger, así que se generan aquí una sola vez).
-- -----------------------------------------------------
INSERT INTO multas (prestamo_id, dias_retraso, monto)
SELECT
    prestamo_id,
    fecha_devolucion - fecha_vencimiento,
    calcular_multa(fecha_devolucion - fecha_vencimiento)
FROM prestamos
WHERE fecha_devolucion > fecha_vencimiento;
