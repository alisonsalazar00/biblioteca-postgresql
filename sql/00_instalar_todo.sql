-- =====================================================
-- Sistema de Biblioteca - Instalación completa
--
-- Ejecuta todos los scripts en el orden correcto.
-- Se usa desde la terminal con psql, PARADO en esta carpeta (sql/):
--
--     psql -U postgres -d biblioteca -f 00_instalar_todo.sql
--
-- (En pgAdmin no funciona \i: allí se abren y ejecutan los
--  archivos uno por uno, en el mismo orden.)
--
-- Antes hay que crear la base de datos vacía:
--     CREATE DATABASE biblioteca;
-- =====================================================

\set ON_ERROR_STOP on

\echo '--- 01: esquema'
\i 01_schema.sql
\echo '--- 02: datos de prueba'
\i 02_datos_prueba_parte1.sql
\i 02_datos_prueba_parte2.sql
\i 02_datos_prueba_parte3.sql
\i 02_datos_prueba_parte4.sql
\echo '--- 03: consultas de ejemplo (solo lectura)'
\i 03_consultas.sql
\echo '--- 04: vistas'
\i 04_vistas.sql
\echo '--- 05: funciones y triggers de préstamos'
\i 05_funciones_triggers.sql
\echo '--- 06: multas'
\i 06_multas.sql
\echo '--- 07: usuarios'
\i 07_usuarios.sql
\echo '--- 08: cuentas y roles'
\i 08_cuentas.sql
\echo '--- 09: auditoría y correcciones'
\i 09_auditoria.sql
\echo '--- 10: vistas analíticas del panel'
\i 10_panel.sql
\echo '--- 11: gestión del catálogo'
\i 11_catalogo.sql
\echo '--- 12: solicitudes de préstamo'
\i 12_solicitudes.sql
\echo '--- Listo: base de datos instalada'
