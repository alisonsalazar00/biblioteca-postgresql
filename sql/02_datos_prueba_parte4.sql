-- =====================================================
-- Sistema de Biblioteca - Datos de prueba
-- Parte 4: préstamos
-- (ejecutar DESPUÉS de las partes 1, 2 y 3)
-- =====================================================

-- -----------------------------------------------------
-- Préstamos
-- Las fechas son relativas a hoy (CURRENT_DATE):
--   dias     = hace cuántos días se prestó el ejemplar
--   dev_dias = hace cuántos días se devolvió (NULL = sigue prestado)
-- El plazo de préstamo es de 14 días.
-- El ejemplar y el usuario se buscan por código de barras y correo.
-- -----------------------------------------------------
INSERT INTO prestamos (ejemplar_id, usuario_id, fecha_prestamo, fecha_vencimiento, fecha_devolucion)
SELECT
    e.ejemplar_id,
    u.usuario_id,
    CURRENT_DATE - v.dias,
    CURRENT_DATE - v.dias + 14,
    CURRENT_DATE - v.dev_dias
FROM (VALUES
    -- Ya devueltos (algunos a tiempo, otros con retraso)
    ('BIB-0012', 'mateo.salas@example.com',      200, 190),
    ('BIB-0001', 'sofia.jimenez@example.com',    120, 108),
    ('BIB-0001', 'andres.mora@example.com',      100,  80),
    ('BIB-0004', 'valeria.rojas@example.com',     90,  78),
    ('BIB-0006', 'diego.vargas@example.com',      75,  62),
    ('BIB-0010', 'camila.solis@example.com',      60,  41),
    ('BIB-0013', 'sofia.jimenez@example.com',     55,  45),
    ('BIB-0016', 'daniel.araya@example.com',      45,  33),
    ('BIB-0001', 'paola.chaves@example.com',      40,  30),
    ('BIB-0008', 'esteban.quesada@example.com',   35,  22),
    ('BIB-0018', 'lucia.hernandez@example.com',   30,  20),
    ('BIB-0013', 'andres.mora@example.com',       28,  15),
    ('BIB-0021', 'sofia.jimenez@example.com',     25,  12),

    -- Activos y al día (aún no vencen)
    ('BIB-0002', 'valeria.rojas@example.com',      5, NULL),
    ('BIB-0015', 'diego.vargas@example.com',       3, NULL),
    ('BIB-0005', 'lucia.hernandez@example.com',   10, NULL),

    -- Activos y vencidos (no se han devuelto y ya pasó la fecha)
    ('BIB-0003', 'daniel.araya@example.com',      30, NULL),
    ('BIB-0007', 'camila.solis@example.com',      22, NULL),
    ('BIB-0009', 'esteban.quesada@example.com',   18, NULL),
    ('BIB-0014', 'paola.chaves@example.com',      16, NULL)
) AS v(codigo, email, dias, dev_dias)
JOIN ejemplares e ON e.codigo_barras = v.codigo
JOIN usuarios   u ON u.email = v.email;

-- -----------------------------------------------------
-- Los ejemplares con préstamo activo pasan a estado 'prestado'
-- (más adelante esto lo hará un trigger automáticamente)
-- -----------------------------------------------------
UPDATE ejemplares
SET estado = 'prestado'
WHERE ejemplar_id IN (
    SELECT ejemplar_id
    FROM prestamos
    WHERE fecha_devolucion IS NULL
);
