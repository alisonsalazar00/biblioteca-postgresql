-- =====================================================
-- Sistema de Biblioteca - Datos de prueba
-- Parte 3: ejemplares y usuarios
-- (ejecutar DESPUÉS de las partes 1 y 2)
-- =====================================================

-- -----------------------------------------------------
-- Ejemplares
-- El libro se busca por ISBN para no depender de los IDs.
-- Algunos libros tienen más de una copia.
-- -----------------------------------------------------
INSERT INTO ejemplares (libro_id, codigo_barras, estado)
SELECT l.libro_id, v.codigo, v.estado
FROM (VALUES
    ('978-0-000-00001-1', 'BIB-0001', 'disponible'),
    ('978-0-000-00001-1', 'BIB-0002', 'disponible'),
    ('978-0-000-00001-1', 'BIB-0003', 'disponible'),
    ('978-0-000-00002-2', 'BIB-0004', 'disponible'),
    ('978-0-000-00002-2', 'BIB-0005', 'disponible'),
    ('978-0-000-00003-3', 'BIB-0006', 'disponible'),
    ('978-0-000-00003-3', 'BIB-0007', 'disponible'),
    ('978-0-000-00004-4', 'BIB-0008', 'disponible'),
    ('978-0-000-00004-4', 'BIB-0009', 'disponible'),
    ('978-0-000-00005-5', 'BIB-0010', 'disponible'),
    ('978-0-000-00005-5', 'BIB-0011', 'en_reparacion'),
    ('978-0-000-00006-6', 'BIB-0012', 'disponible'),
    ('978-0-000-00007-7', 'BIB-0013', 'disponible'),
    ('978-0-000-00007-7', 'BIB-0014', 'disponible'),
    ('978-0-000-00008-8', 'BIB-0015', 'disponible'),
    ('978-0-000-00009-9', 'BIB-0016', 'disponible'),
    ('978-0-000-00009-9', 'BIB-0017', 'disponible'),
    ('978-0-000-00010-0', 'BIB-0018', 'disponible'),
    ('978-0-000-00010-0', 'BIB-0019', 'disponible'),
    ('978-0-000-00011-1', 'BIB-0020', 'disponible'),
    ('978-0-000-00012-2', 'BIB-0021', 'disponible'),
    ('978-0-000-00012-2', 'BIB-0022', 'disponible'),
    ('978-0-000-00013-3', 'BIB-0023', 'disponible'),
    ('978-0-000-00014-4', 'BIB-0024', 'disponible')
) AS v(isbn, codigo, estado)
JOIN libros l ON l.isbn = v.isbn;

-- -----------------------------------------------------
-- Usuarios
-- Nota: los correos y teléfonos son ficticios.
-- El último usuario está inactivo, para practicar filtros.
-- -----------------------------------------------------
INSERT INTO usuarios (nombre, apellido, email, telefono, fecha_registro, activo) VALUES
    ('Sofía',   'Jiménez',   'sofia.jimenez@example.com',   '8812-3456', '2024-02-10', TRUE),
    ('Andrés',  'Mora',      'andres.mora@example.com',     '8823-4567', '2024-03-15', TRUE),
    ('Valeria', 'Rojas',     'valeria.rojas@example.com',   '8834-5678', '2024-05-02', TRUE),
    ('Diego',   'Vargas',    'diego.vargas@example.com',    '8845-6789', '2024-06-20', TRUE),
    ('Camila',  'Solís',     'camila.solis@example.com',    '8856-7890', '2024-08-09', TRUE),
    ('Daniel',  'Araya',     'daniel.araya@example.com',    '8867-8901', '2024-09-18', TRUE),
    ('Paola',   'Chaves',    'paola.chaves@example.com',    '8878-9012', '2025-01-07', TRUE),
    ('Esteban', 'Quesada',   'esteban.quesada@example.com', '8889-0123', '2025-02-25', TRUE),
    ('Lucía',   'Hernández', 'lucia.hernandez@example.com', '8890-1234', '2025-04-12', TRUE),
    ('Mateo',   'Salas',     'mateo.salas@example.com',     '8801-2345', '2023-11-30', FALSE);
