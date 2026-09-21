"""Conexión a PostgreSQL y funciones auxiliares para consultar la base."""
import os

import psycopg
from psycopg.rows import dict_row
from dotenv import load_dotenv

# Lee las credenciales del archivo .env (que no se sube a GitHub)
load_dotenv()


def get_connection():
    """Abre una conexión nueva a la base de datos."""
    return psycopg.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "biblioteca"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD"),
        row_factory=dict_row,  # cada fila llega como diccionario
    )


def query(sql, params=None):
    """Ejecuta un SELECT y devuelve todas las filas como una lista de diccionarios."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchall()


def call(sql, params=None):
    """Ejecuta una función de PostgreSQL que modifica datos y devuelve su resultado.

    Al terminar sin errores, la conexión guarda (commit) los cambios.
    Si la función lanza un error, se deshace todo (rollback).
    """
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()