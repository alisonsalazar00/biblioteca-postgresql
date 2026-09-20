-- =====================================================
-- Sistema de Biblioteca - Datos de prueba
-- Parte 1: categorías y autores
-- =====================================================

-- -----------------------------------------------------
-- Categorías
-- -----------------------------------------------------
INSERT INTO categorias (nombre) VALUES
    ('Novela'),
    ('Cuento'),
    ('Poesía'),
    ('Ensayo'),
    ('Historia'),
    ('Ciencia ficción');

-- -----------------------------------------------------
-- Autores
-- -----------------------------------------------------
INSERT INTO autores (nombre, apellido, nacionalidad, fecha_nacimiento) VALUES
    ('Gabriel',  'García Márquez', 'Colombiana',    '1927-03-06'),
    ('Isabel',   'Allende',        'Chilena',       '1942-08-02'),
    ('Julio',    'Cortázar',       'Argentina',     '1914-08-26'),
    ('Jorge Luis', 'Borges',       'Argentina',     '1899-08-24'),
    ('Mario',    'Vargas Llosa',   'Peruana',       '1936-03-28'),
    ('Carmen',   'Naranjo',        'Costarricense', '1928-02-05'),
    ('Carlos Luis', 'Fallas',      'Costarricense', '1909-01-21'),
    ('Gioconda', 'Belli',          'Nicaragüense',  '1948-12-09');
