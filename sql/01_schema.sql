-- =====================================================
-- Sistema de Biblioteca - Esquema de base de datos
-- Motor: PostgreSQL
-- =====================================================

DROP TABLE IF EXISTS prestamos CASCADE;
DROP TABLE IF EXISTS ejemplares CASCADE;
DROP TABLE IF EXISTS libros_autores CASCADE;
DROP TABLE IF EXISTS libros CASCADE;
DROP TABLE IF EXISTS autores CASCADE;
DROP TABLE IF EXISTS categorias CASCADE;
DROP TABLE IF EXISTS usuarios CASCADE;

-- -----------------------------------------------------
-- Autores
-- -----------------------------------------------------
CREATE TABLE autores (
    autor_id         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre           VARCHAR(100) NOT NULL,
    apellido         VARCHAR(100) NOT NULL,
    nacionalidad     VARCHAR(60),
    fecha_nacimiento DATE
);

-- -----------------------------------------------------
-- Categorías
-- -----------------------------------------------------
CREATE TABLE categorias (
    categoria_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre       VARCHAR(80) NOT NULL UNIQUE
);

-- -----------------------------------------------------
-- Libros (el "título" como obra, no la copia física)
-- -----------------------------------------------------
CREATE TABLE libros (
    libro_id         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    isbn             VARCHAR(20) NOT NULL UNIQUE,
    titulo           VARCHAR(200) NOT NULL,
    anio_publicacion SMALLINT CHECK (anio_publicacion BETWEEN 1000 AND 2100),
    categoria_id     INT NOT NULL REFERENCES categorias (categoria_id)
);

-- -----------------------------------------------------
-- Relación N:M entre libros y autores
-- -----------------------------------------------------
CREATE TABLE libros_autores (
    libro_id INT NOT NULL REFERENCES libros (libro_id) ON DELETE CASCADE,
    autor_id INT NOT NULL REFERENCES autores (autor_id) ON DELETE CASCADE,
    PRIMARY KEY (libro_id, autor_id)
);

-- -----------------------------------------------------
-- Ejemplares (copias físicas de un libro)
-- -----------------------------------------------------
CREATE TABLE ejemplares (
    ejemplar_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    libro_id      INT NOT NULL REFERENCES libros (libro_id),
    codigo_barras VARCHAR(30) NOT NULL UNIQUE,
    estado        VARCHAR(20) NOT NULL DEFAULT 'disponible'
                  CHECK (estado IN ('disponible', 'prestado', 'en_reparacion', 'perdido'))
);

-- -----------------------------------------------------
-- Usuarios
-- -----------------------------------------------------
CREATE TABLE usuarios (
    usuario_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre         VARCHAR(100) NOT NULL,
    apellido       VARCHAR(100) NOT NULL,
    email          VARCHAR(150) NOT NULL UNIQUE,
    telefono       VARCHAR(20),
    fecha_registro DATE NOT NULL DEFAULT CURRENT_DATE,
    activo         BOOLEAN NOT NULL DEFAULT TRUE
);

-- -----------------------------------------------------
-- Préstamos
-- -----------------------------------------------------
CREATE TABLE prestamos (
    prestamo_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ejemplar_id       INT NOT NULL REFERENCES ejemplares (ejemplar_id),
    usuario_id        INT NOT NULL REFERENCES usuarios (usuario_id),
    fecha_prestamo    DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_vencimiento DATE NOT NULL,
    fecha_devolucion  DATE,
    CHECK (fecha_vencimiento >= fecha_prestamo),
    CHECK (fecha_devolucion IS NULL OR fecha_devolucion >= fecha_prestamo)
);

-- Un mismo ejemplar no puede tener dos préstamos activos a la vez
CREATE UNIQUE INDEX uq_prestamo_activo_por_ejemplar
    ON prestamos (ejemplar_id)
    WHERE fecha_devolucion IS NULL;

-- -----------------------------------------------------
-- Índices sobre llaves foráneas (mejoran los JOIN)
-- -----------------------------------------------------
CREATE INDEX idx_libros_categoria    ON libros (categoria_id);
CREATE INDEX idx_ejemplares_libro    ON ejemplares (libro_id);
CREATE INDEX idx_prestamos_usuario   ON prestamos (usuario_id);
CREATE INDEX idx_libros_autores_autor ON libros_autores (autor_id);
