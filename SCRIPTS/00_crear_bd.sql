-- ##### ARCHIVO: 00_crear_bd.sql #####
/* =====================================================================
   00_crear_bd.sql
   Crea la base de datos vacía. ATENCIÓN: elimina la anterior si existe.
   ===================================================================== */
DROP DATABASE IF EXISTS Proyecto_SistemasVentasGranilocas_V2;

CREATE DATABASE Proyecto_SistemasVentasGranilocas_V2
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;   -- ai = ignora tildes, ci = ignora mayúsculas

USE Proyecto_SistemasVentasGranilocas_V2;
