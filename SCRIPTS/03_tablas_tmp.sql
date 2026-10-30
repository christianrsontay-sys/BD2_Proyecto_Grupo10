-- ##### ARCHIVO: 03_tablas_tmp.sql #####
/* =====================================================================
   03_tablas_tmp.sql
   Tabla temporal (staging): una columna por campo del CSV, todo texto,
   para que la carga nunca falle por tipos.
   ===================================================================== */
USE Proyecto_SistemasVentasGranilocas_V2;

DROP TABLE IF EXISTS tmp_ventas;

CREATE TABLE tmp_ventas (
    numero_factura           VARCHAR(20),
    fecha_venta              VARCHAR(20),    -- dd/mm/aaaa
    hora_venta               VARCHAR(10),
    linea                    VARCHAR(10),
    codigo_sucursal          VARCHAR(10),
    nombre_sucursal          VARCHAR(60),
    direccion_sucursal       VARCHAR(150),
    municipio_sucursal       VARCHAR(60),
    departamento_sucursal    VARCHAR(60),
    codigo_vendedor          VARCHAR(10),
    nombres_vendedor         VARCHAR(60),
    apellidos_vendedor       VARCHAR(60),
    nit_cliente              VARCHAR(20),
    nombres_cliente          VARCHAR(60),
    apellidos_cliente        VARCHAR(60),
    genero_cliente           VARCHAR(5),
    fecha_nacimiento_cliente VARCHAR(20),
    telefono_cliente         VARCHAR(20),
    correo_cliente           VARCHAR(120),
    direccion_cliente        VARCHAR(150),
    municipio_cliente        VARCHAR(60),
    departamento_cliente     VARCHAR(60),
    codigo_producto          VARCHAR(10),
    nombre_producto          VARCHAR(120),
    categoria                VARCHAR(60),
    marca                    VARCHAR(60),
    precio_unitario          VARCHAR(20),
    cantidad                 VARCHAR(10),
    subtotal                 VARCHAR(20),
    metodo_pago              VARCHAR(20)
);

ALTER TABLE tmp_ventas CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
