-- =====================================================
-- Sistema de Biblioteca - Datos de prueba
-- Parte 2: libros y relación libros_autores
-- (ejecutar DESPUÉS de la parte 1)
-- =====================================================

-- -----------------------------------------------------
-- Libros
-- Nota: los ISBN son ficticios, solo para pruebas.
-- La categoría se busca por nombre para no depender de los IDs.
-- -----------------------------------------------------
INSERT INTO libros (isbn, titulo, anio_publicacion, categoria_id)
SELECT v.isbn, v.titulo, v.anio, c.categoria_id
FROM (VALUES
    ('978-0-000-00001-1', 'Cien años de soledad',                        1967, 'Novela'),
    ('978-0-000-00002-2', 'El amor en los tiempos del cólera',           1985, 'Novela'),
    ('978-0-000-00003-3', 'Crónica de una muerte anunciada',             1981, 'Novela'),
    ('978-0-000-00004-4', 'La casa de los espíritus',                    1982, 'Novela'),
    ('978-0-000-00005-5', 'Rayuela',                                     1963, 'Novela'),
    ('978-0-000-00006-6', 'Bestiario',                                   1951, 'Cuento'),
    ('978-0-000-00007-7', 'Ficciones',                                   1944, 'Cuento'),
    ('978-0-000-00008-8', 'El Aleph',                                    1949, 'Cuento'),
    ('978-0-000-00009-9', 'La ciudad y los perros',                      1963, 'Novela'),
    ('978-0-000-00010-0', 'Mamita Yunai',                                1941, 'Novela'),
    ('978-0-000-00011-1', 'Diario de una multitud',                      1974, 'Novela'),
    ('978-0-000-00012-2', 'La mujer habitada',                           1988, 'Novela'),
    ('978-0-000-00013-3', 'Línea de fuego',                              1978, 'Poesía'),
    ('978-0-000-00014-4', 'La novela en América Latina: diálogo',        1968, 'Ensayo')
) AS v(isbn, titulo, anio, categoria)
JOIN categorias c ON c.nombre = v.categoria;

-- -----------------------------------------------------
-- Relación libros - autores (N:M)
-- El último libro tiene dos autores, para mostrar la relación N:M.
-- -----------------------------------------------------
INSERT INTO libros_autores (libro_id, autor_id)
SELECT l.libro_id, a.autor_id
FROM (VALUES
    ('978-0-000-00001-1', 'García Márquez'),
    ('978-0-000-00002-2', 'García Márquez'),
    ('978-0-000-00003-3', 'García Márquez'),
    ('978-0-000-00004-4', 'Allende'),
    ('978-0-000-00005-5', 'Cortázar'),
    ('978-0-000-00006-6', 'Cortázar'),
    ('978-0-000-00007-7', 'Borges'),
    ('978-0-000-00008-8', 'Borges'),
    ('978-0-000-00009-9', 'Vargas Llosa'),
    ('978-0-000-00010-0', 'Fallas'),
    ('978-0-000-00011-1', 'Naranjo'),
    ('978-0-000-00012-2', 'Belli'),
    ('978-0-000-00013-3', 'Belli'),
    ('978-0-000-00014-4', 'García Márquez'),
    ('978-0-000-00014-4', 'Vargas Llosa')
) AS v(isbn, apellido)
JOIN libros  l ON l.isbn = v.isbn
JOIN autores a ON a.apellido = v.apellido;
