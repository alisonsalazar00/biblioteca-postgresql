-- =====================================================
-- Sistema de Biblioteca - Consultas
-- Nivel 1: consultas básicas
-- =====================================================


-- -----------------------------------------------------
-- 1. Ejemplares disponibles por libro
-- Cuenta cuántas copias de cada título se pueden prestar hoy.
-- Un libro sin copias disponibles no aparece en el resultado.
-- -----------------------------------------------------
SELECT
    l.titulo,
    COUNT(*) AS copias_disponibles
FROM libros l
JOIN ejemplares e ON e.libro_id = l.libro_id
WHERE e.estado = 'disponible'
GROUP BY l.titulo
ORDER BY copias_disponibles DESC, l.titulo;


-- -----------------------------------------------------
-- 2. Préstamos activos
-- Muestra quién tiene qué libro y cuándo debe devolverlo.
-- Un préstamo está activo cuando aún no tiene fecha de devolución.
-- -----------------------------------------------------
SELECT
    u.nombre || ' ' || u.apellido AS usuario,
    l.titulo,
    p.fecha_prestamo,
    p.fecha_vencimiento
FROM prestamos p
JOIN usuarios  u ON u.usuario_id  = p.usuario_id
JOIN ejemplares e ON e.ejemplar_id = p.ejemplar_id
JOIN libros    l ON l.libro_id    = e.libro_id
WHERE p.fecha_devolucion IS NULL
ORDER BY p.fecha_vencimiento;


-- -----------------------------------------------------
-- 3. Préstamos vencidos y días de retraso
-- Igual que la anterior, pero solo los que ya pasaron su fecha
-- de vencimiento. Restar dos fechas en PostgreSQL da la
-- diferencia en días.
-- -----------------------------------------------------
SELECT
    u.nombre || ' ' || u.apellido AS usuario,
    u.email,
    l.titulo,
    p.fecha_vencimiento,
    CURRENT_DATE - p.fecha_vencimiento AS dias_retraso
FROM prestamos p
JOIN usuarios  u ON u.usuario_id  = p.usuario_id
JOIN ejemplares e ON e.ejemplar_id = p.ejemplar_id
JOIN libros    l ON l.libro_id    = e.libro_id
WHERE p.fecha_devolucion IS NULL
AND p.fecha_vencimiento < CURRENT_DATE
ORDER BY dias_retraso DESC;

-- =====================================================
-- Nivel 2: agrupaciones, rankings y LEFT JOIN
-- =====================================================

-- -----------------------------------------------------
-- 4. Los 5 libros más prestados
-- Cada libro puede tener varias copias, así que se suman los
-- préstamos de todos sus ejemplares. LIMIT recorta el ranking.
-- -----------------------------------------------------
SELECT
    l.titulo,
    COUNT(p.prestamo_id) AS veces_prestado
FROM libros l
JOIN ejemplares e ON e.libro_id    = l.libro_id
JOIN prestamos  p ON p.ejemplar_id = e.ejemplar_id
GROUP BY l.libro_id, l.titulo
ORDER BY veces_prestado DESC, l.titulo
LIMIT 5;

-- -----------------------------------------------------
-- 5. Devoluciones tardías
-- Préstamos que SÍ se devolvieron, pero después de la fecha
-- de vencimiento. Sirve para ver qué usuarios se atrasan.
-- -----------------------------------------------------
SELECT
    u.nombre || ' ' || u.apellido AS usuario,
    l.titulo,
    p.fecha_vencimiento,
    p.fecha_devolucion,
    p.fecha_devolucion - p.fecha_vencimiento AS dias_de_retraso
FROM prestamos p
JOIN usuarios   u ON u.usuario_id  = p.usuario_id
JOIN ejemplares e ON e.ejemplar_id = p.ejemplar_id
JOIN libros     l ON l.libro_id    = e.libro_id
WHERE p.fecha_devolucion > p.fecha_vencimiento
ORDER BY dias_de_retraso DESC;

-- -----------------------------------------------------
-- 6. Libros que nunca se han prestado
-- LEFT JOIN conserva todos los libros, aunque no tengan
-- préstamos. HAVING filtra después de agrupar (WHERE no
-- puede usar COUNT).
-- -----------------------------------------------------
SELECT l.titulo
FROM libros l
LEFT JOIN ejemplares e ON e.libro_id    = l.libro_id
LEFT JOIN prestamos  p ON p.ejemplar_id = e.ejemplar_id
GROUP BY l.libro_id, l.titulo
HAVING COUNT(p.prestamo_id) = 0
ORDER BY l.titulo;