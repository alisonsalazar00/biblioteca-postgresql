-- =====================================================
-- Sistema de Biblioteca - Vistas
-- Se pueden ejecutar varias veces sin problema
-- (CREATE OR REPLACE actualiza la vista si ya existe).
-- =====================================================


-- -----------------------------------------------------
-- v_catalogo
-- Cada libro con sus autores, su categoría y cuántas copias
-- tiene en total y disponibles. Los autores se unen en una
-- sola columna con string_agg. Se usan subconsultas para que
-- ni los autores ni las copias multipliquen las filas.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_catalogo AS
SELECT
    l.libro_id,
    l.titulo,
    (
        SELECT string_agg(a.nombre || ' ' || a.apellido, ', ' ORDER BY a.apellido)
        FROM libros_autores la
        JOIN autores a ON a.autor_id = la.autor_id
        WHERE la.libro_id = l.libro_id
    ) AS autores,
    c.nombre AS categoria,
    l.anio_publicacion,
    (
        SELECT COUNT(*)
        FROM ejemplares e
        WHERE e.libro_id = l.libro_id
    ) AS total_copias,
    (
        SELECT COUNT(*)
        FROM ejemplares e
        WHERE e.libro_id = l.libro_id
          AND e.estado = 'disponible'
    ) AS copias_disponibles
FROM libros l
JOIN categorias c ON c.categoria_id = l.categoria_id;


-- -----------------------------------------------------
-- v_prestamos_activos
-- Préstamos que aún no se han devuelto, con los datos del
-- usuario y del libro ya unidos. dias_retraso vale 0 si el
-- préstamo todavía no vence.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_prestamos_activos AS
SELECT
    p.prestamo_id,
    e.codigo_barras,
    l.titulo,
    u.nombre || ' ' || u.apellido AS usuario,
    u.email,
    p.fecha_prestamo,
    p.fecha_vencimiento,
    GREATEST(CURRENT_DATE - p.fecha_vencimiento, 0) AS dias_retraso
FROM prestamos p
JOIN usuarios   u ON u.usuario_id  = p.usuario_id
JOIN ejemplares e ON e.ejemplar_id = p.ejemplar_id
JOIN libros     l ON l.libro_id    = e.libro_id
WHERE p.fecha_devolucion IS NULL;


-- -----------------------------------------------------
-- v_prestamos_vencidos
-- Construida sobre otra vista: solo los préstamos activos
-- que ya pasaron su fecha de vencimiento.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_prestamos_vencidos AS
SELECT *
FROM v_prestamos_activos
WHERE dias_retraso > 0;
