-- =====================================================
-- Sistema de Biblioteca - Vistas analíticas del panel
-- Ejecutar DESPUÉS de 01 a 09.
-- Se puede ejecutar varias veces sin problema.
--
-- Estas vistas usan funciones de ventana (RANK, LAG, SUM OVER),
-- que calculan sobre un conjunto de filas SIN colapsarlas como
-- haría un GROUP BY: cada fila conserva su detalle y además
-- recibe un valor calculado a partir de las demás.
-- =====================================================


-- -----------------------------------------------------
-- v_panel_resumen
-- Una sola fila con las cifras principales de la biblioteca.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_panel_resumen AS
SELECT
    (SELECT COUNT(*) FROM prestamos
      WHERE fecha_devolucion IS NULL)                              AS prestamos_activos,
    (SELECT COUNT(*) FROM prestamos
      WHERE fecha_devolucion IS NULL
        AND fecha_vencimiento < CURRENT_DATE)                      AS prestamos_vencidos,
    (SELECT COUNT(*) FROM ejemplares
      WHERE estado = 'disponible')                                 AS ejemplares_disponibles,
    (SELECT COUNT(*) FROM ejemplares)                              AS ejemplares_total,
    (SELECT COUNT(*) FROM usuarios WHERE activo)                   AS usuarios_activos,
    (SELECT COUNT(*) FROM multas WHERE NOT pagada)                 AS multas_pendientes,
    (SELECT COALESCE(SUM(monto), 0) FROM multas
      WHERE NOT pagada)                                            AS monto_pendiente,
    -- Porcentaje de préstamos ya devueltos que se entregaron a tiempo
    (SELECT ROUND(100.0
                  * COUNT(*) FILTER (WHERE fecha_devolucion <= fecha_vencimiento)
                  / NULLIF(COUNT(*), 0), 0)
       FROM prestamos
      WHERE fecha_devolucion IS NOT NULL)                          AS pct_a_tiempo;


-- -----------------------------------------------------
-- v_prestamos_por_mes
-- Los préstamos de cada uno de los últimos 12 meses.
-- generate_series crea los 12 meses aunque alguno no tenga
-- préstamos (con LEFT JOIN aparecen en cero, sin huecos).
-- LAG mira la fila anterior para calcular la variación
-- respecto al mes previo.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_prestamos_por_mes AS
SELECT
    m.mes::DATE                                                     AS mes,
    COUNT(p.prestamo_id)                                            AS prestamos,
    COUNT(p.prestamo_id)
        - LAG(COUNT(p.prestamo_id)) OVER (ORDER BY m.mes)           AS variacion
FROM generate_series(
         date_trunc('month', CURRENT_DATE::TIMESTAMP) - INTERVAL '11 months',
         date_trunc('month', CURRENT_DATE::TIMESTAMP),
         INTERVAL '1 month'
     ) AS m(mes)
LEFT JOIN prestamos p
       ON date_trunc('month', p.fecha_prestamo::TIMESTAMP) = m.mes
GROUP BY m.mes;


-- -----------------------------------------------------
-- v_ranking_libros
-- Cuántas veces se ha prestado cada libro y su posición.
-- RANK da la misma posición a los empates (dos libros con 3
-- préstamos son ambos el 2.º, y el siguiente es el 4.º).
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_ranking_libros AS
SELECT
    l.libro_id,
    l.titulo,
    COUNT(p.prestamo_id)                                    AS veces_prestado,
    RANK() OVER (ORDER BY COUNT(p.prestamo_id) DESC)        AS posicion
FROM libros l
JOIN ejemplares e ON e.libro_id    = l.libro_id
JOIN prestamos  p ON p.ejemplar_id = e.ejemplar_id
GROUP BY l.libro_id, l.titulo;


-- -----------------------------------------------------
-- v_uso_categorias
-- Préstamos por categoría y qué porcentaje del total son.
-- SUM(...) OVER () suma todas las filas del resultado, así cada
-- categoría se compara contra el total sin una segunda consulta.
-- NULLIF evita dividir entre cero si aún no hay préstamos.
-- -----------------------------------------------------
CREATE OR REPLACE VIEW v_uso_categorias AS
SELECT
    c.nombre                                                AS categoria,
    COUNT(p.prestamo_id)                                    AS prestamos,
    ROUND(100.0 * COUNT(p.prestamo_id)
          / NULLIF(SUM(COUNT(p.prestamo_id)) OVER (), 0), 1) AS porcentaje
FROM categorias c
LEFT JOIN libros     l ON l.categoria_id = c.categoria_id
LEFT JOIN ejemplares e ON e.libro_id     = l.libro_id
LEFT JOIN prestamos  p ON p.ejemplar_id  = e.ejemplar_id
GROUP BY c.categoria_id, c.nombre;
