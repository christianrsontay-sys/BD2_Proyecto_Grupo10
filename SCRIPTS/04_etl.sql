-- ##### ARCHIVO: 04_etl.sql #####
/* =====================================================================
   04_etl.sql
   Carga del CSV a tmp_ventas y migración al modelo normalizado.
   Importante: se ejecuta ANTES de crear los triggers (06), así la
   bitácora no se llena con miles de registros de la carga inicial.
   ===================================================================== */
USE Proyecto_SistemasVentasGranilocas_V2;

-- ---------- 1. Carga del CSV a la tabla temporal ----------
-- Revise estas variables si la carga falla (enunciado 6.7):
--   secure_file_priv = carpeta desde la que el servidor permite leer archivos
--   local_infile     = debe estar en ON para usar LOAD DATA LOCAL INFILE
SELECT @@secure_file_priv, @@local_infile;
TRUNCATE TABLE tmp_ventas;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/ventas.csv'
INTO TABLE tmp_ventas
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES;

/* ALTERNATIVA (Anexo B): carga desde el equipo del cliente, con LOCAL.
   Requiere SET GLOBAL local_infile = 1 y, en Workbench, activar
   OPT_LOCAL_INFILE=1 en Connection > Advanced > Others.
   Cambie la ruta y el separador (',' o ';') según el CSV recibido.

LOAD DATA LOCAL INFILE 'C:/datos/ventas.csv'
INTO TABLE tmp_ventas
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ';' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES;
*/

SELECT COUNT(*) AS filas_en_tmp FROM tmp_ventas;

-- ---------- 2. ETL parte 1: geografía, sucursal, categoría, marca, producto ----------
DROP PROCEDURE IF EXISTS sp_etl_cargar_datos;
DELIMITER //

CREATE PROCEDURE sp_etl_cargar_datos()
BEGIN
    DECLARE v_inicio DATETIME DEFAULT NOW();
    DECLARE v_filas INT DEFAULT 0;
    DECLARE v_resumen VARCHAR(500) DEFAULT '';
    DECLARE v_mensaje TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_mensaje = MESSAGE_TEXT;
        ROLLBACK;
        INSERT INTO etl_control
            (fecha_inicio, fecha_fin, filas_leidas, filas_insertadas, estado, mensaje)
        VALUES
            (v_inicio, NOW(), v_filas, NULL, 'FALLIDO', v_mensaje);
        RESIGNAL;
    END;

    SELECT COUNT(*) INTO v_filas FROM tmp_ventas;

    IF v_filas = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-01] La tabla tmp_ventas está vacía. Cargue primero el CSV.';
    END IF;

    IF EXISTS (SELECT 1 FROM sucursal) OR EXISTS (SELECT 1 FROM producto) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-02] El modelo ya contiene datos. Ejecute el ETL sobre una base recién creada.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM tmp_ventas
        WHERE STR_TO_DATE(fecha_venta, '%d/%m/%Y') IS NULL
           OR precio_unitario NOT REGEXP '^[0-9]+(\\.[0-9]{1,2})?$'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-03] Hay fechas o precios con formato inválido en tmp_ventas.';
    END IF;

    IF EXISTS (
        SELECT codigo_sucursal FROM tmp_ventas
        GROUP BY codigo_sucursal
        HAVING COUNT(DISTINCT nombre_sucursal) > 1
            OR COUNT(DISTINCT direccion_sucursal) > 1
            OR COUNT(DISTINCT municipio_sucursal) > 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-04] Una sucursal aparece con datos distintos en el archivo.';
    END IF;

    IF EXISTS (
        SELECT codigo_producto FROM tmp_ventas
        GROUP BY codigo_producto
        HAVING COUNT(DISTINCT nombre_producto) > 1
            OR COUNT(DISTINCT categoria) > 1
            OR COUNT(DISTINCT marca) > 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-05] Un producto aparece con nombre, categoría o marca distintos.';
    END IF;

    START TRANSACTION;

    INSERT INTO departamento (nombre)
    SELECT departamento_sucursal FROM tmp_ventas
    UNION
    SELECT departamento_cliente FROM tmp_ventas;
    SET v_resumen = CONCAT('departamento=', ROW_COUNT());

    INSERT INTO municipio (nombre, id_departamento)
    SELECT u.municipio, d.id_departamento
    FROM (
        SELECT municipio_sucursal AS municipio, departamento_sucursal AS departamento FROM tmp_ventas
        UNION
        SELECT municipio_cliente, departamento_cliente FROM tmp_ventas
    ) AS u
    JOIN departamento d ON d.nombre = u.departamento;
    SET v_resumen = CONCAT(v_resumen, '; municipio=', ROW_COUNT());

    INSERT INTO sucursal (codigo, nombre, direccion, id_municipio)
    SELECT DISTINCT t.codigo_sucursal, t.nombre_sucursal, t.direccion_sucursal, m.id_municipio
    FROM tmp_ventas t
    JOIN departamento d ON d.nombre = t.departamento_sucursal
    JOIN municipio m    ON m.nombre = t.municipio_sucursal
                       AND m.id_departamento = d.id_departamento;
    SET v_resumen = CONCAT(v_resumen, '; sucursal=', ROW_COUNT());

    INSERT INTO categoria (nombre) SELECT DISTINCT categoria FROM tmp_ventas;
    SET v_resumen = CONCAT(v_resumen, '; categoria=', ROW_COUNT());

    INSERT INTO marca (nombre) SELECT DISTINCT marca FROM tmp_ventas;
    SET v_resumen = CONCAT(v_resumen, '; marca=', ROW_COUNT());

    -- precio_actual = precio de la venta más reciente de cada producto
    INSERT INTO producto (codigo, nombre, id_categoria, id_marca, precio_actual)
    SELECT v.codigo_producto, v.nombre_producto, c.id_categoria, m.id_marca, v.precio
    FROM (
        SELECT codigo_producto, nombre_producto, categoria, marca,
               CAST(precio_unitario AS DECIMAL(12,2)) AS precio,
               ROW_NUMBER() OVER (
                   PARTITION BY codigo_producto
                   ORDER BY STR_TO_DATE(fecha_venta, '%d/%m/%Y') DESC,
                            hora_venta DESC,
                            CAST(numero_factura AS UNSIGNED) DESC
               ) AS rn
        FROM tmp_ventas
    ) AS v
    JOIN categoria c ON c.nombre = v.categoria
    JOIN marca m     ON m.nombre = v.marca
    WHERE v.rn = 1;
    SET v_resumen = CONCAT(v_resumen, '; producto=', ROW_COUNT());

    COMMIT;

    INSERT INTO etl_control
        (fecha_inicio, fecha_fin, filas_leidas, filas_insertadas, estado, mensaje)
    VALUES
        (v_inicio, NOW(), v_filas, v_resumen, 'EXITOSO', NULL);

    SELECT 'ETL ejecutado correctamente' AS mensaje, v_filas AS filas_leidas, v_resumen AS filas_insertadas;
END //

DELIMITER ;

-- ---------- 3. ETL parte 2: vendedor, cliente, factura, detalle_factura ----------
DROP PROCEDURE IF EXISTS sp_etl_cargar_transaccional;
DELIMITER //

CREATE PROCEDURE sp_etl_cargar_transaccional()
BEGIN
    DECLARE v_inicio  DATETIME DEFAULT NOW();
    DECLARE v_filas   INT DEFAULT 0;
    DECLARE v_resumen VARCHAR(500) DEFAULT '';
    DECLARE v_mensaje TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_mensaje = MESSAGE_TEXT;
        ROLLBACK;
        INSERT INTO etl_control
            (fecha_inicio, fecha_fin, filas_leidas, filas_insertadas, estado, mensaje)
        VALUES
            (v_inicio, NOW(), v_filas, NULL, 'FALLIDO', v_mensaje);
        RESIGNAL;
    END;

    SELECT COUNT(*) INTO v_filas FROM tmp_ventas;

    IF v_filas = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-11] La tabla tmp_ventas está vacía.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM sucursal) OR NOT EXISTS (SELECT 1 FROM producto) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-12] Ejecute primero sp_etl_cargar_datos (faltan sucursales/productos).';
    END IF;

    IF EXISTS (SELECT 1 FROM factura) OR EXISTS (SELECT 1 FROM cliente) OR EXISTS (SELECT 1 FROM vendedor) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-13] vendedor, cliente o factura ya contienen datos.';
    END IF;

    -- NIT inválido (usa la función del script 02)
    IF EXISTS (SELECT 1 FROM tmp_ventas WHERE fn_validar_nit(nit_cliente) = 0) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-14] Hay NIT con formato inválido en tmp_ventas.';
    END IF;

    -- Correo inválido (usa la función del script 02)
    IF EXISTS (SELECT 1 FROM tmp_ventas WHERE fn_validar_correo(correo_cliente) = 0) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-15] Hay correos con formato inválido en tmp_ventas.';
    END IF;

    IF EXISTS (SELECT 1 FROM tmp_ventas
               WHERE cantidad NOT REGEXP '^[0-9]+$' OR CAST(cantidad AS UNSIGNED) = 0) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-16] Hay cantidades inválidas (no numéricas, cero o negativas).';
    END IF;

    IF EXISTS (SELECT 1 FROM tmp_ventas t
               LEFT JOIN metodo_pago mp ON mp.nombre = t.metodo_pago
               WHERE mp.id_metodo_pago IS NULL) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-17] Hay métodos de pago que no existen en metodo_pago.';
    END IF;

    IF EXISTS (
        SELECT nit_cliente FROM tmp_ventas
        GROUP BY nit_cliente
        HAVING COUNT(DISTINCT nombres_cliente) > 1
            OR COUNT(DISTINCT apellidos_cliente) > 1
            OR COUNT(DISTINCT genero_cliente) > 1
            OR COUNT(DISTINCT fecha_nacimiento_cliente) > 1
            OR COUNT(DISTINCT correo_cliente) > 1
            OR COUNT(DISTINCT telefono_cliente) > 1
            OR COUNT(DISTINCT direccion_cliente) > 1
            OR COUNT(DISTINCT municipio_cliente) > 1
            OR COUNT(DISTINCT departamento_cliente) > 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-18] Un NIT aparece con datos distintos en el archivo.';
    END IF;

    IF EXISTS (
        SELECT correo_cliente FROM tmp_ventas
        GROUP BY correo_cliente
        HAVING COUNT(DISTINCT nit_cliente) > 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-19] Un correo está asociado a más de un NIT.';
    END IF;

    IF EXISTS (SELECT 1 FROM tmp_ventas
               WHERE genero_cliente NOT IN ('M','F')
                  OR STR_TO_DATE(fecha_nacimiento_cliente, '%d/%m/%Y') IS NULL) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-22] Hay género distinto de M/F o fecha de nacimiento inválida.';
    END IF;

    IF EXISTS (
        SELECT codigo_vendedor FROM tmp_ventas
        GROUP BY codigo_vendedor
        HAVING COUNT(DISTINCT nombres_vendedor) > 1
            OR COUNT(DISTINCT apellidos_vendedor) > 1
            OR COUNT(DISTINCT codigo_sucursal) > 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-23] Un vendedor aparece con datos distintos o en más de una sucursal.';
    END IF;

    IF EXISTS (
        SELECT numero_factura FROM tmp_ventas
        GROUP BY numero_factura
        HAVING COUNT(DISTINCT fecha_venta) > 1
            OR COUNT(DISTINCT hora_venta) > 1
            OR COUNT(DISTINCT codigo_sucursal) > 1
            OR COUNT(DISTINCT codigo_vendedor) > 1
            OR COUNT(DISTINCT nit_cliente) > 1
            OR COUNT(DISTINCT metodo_pago) > 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-20] Una factura tiene datos de cabecera distintos entre sus líneas.';
    END IF;

    IF EXISTS (
        SELECT numero_factura, codigo_producto FROM tmp_ventas
        GROUP BY numero_factura, codigo_producto
        HAVING COUNT(*) > 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-21] Un producto aparece más de una vez en la misma factura.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM tmp_ventas
        WHERE subtotal NOT REGEXP '^[0-9]+(\\.[0-9]{1,2})?$'
           OR ABS(CAST(subtotal AS DECIMAL(12,2))
                  - CAST(cantidad AS UNSIGNED) * CAST(precio_unitario AS DECIMAL(12,2))) > 0.01
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-ETL-24] Hay subtotales que no coinciden con cantidad * precio_unitario.';
    END IF;

    START TRANSACTION;

    INSERT INTO vendedor (codigo, nombres, apellidos, id_sucursal)
    SELECT DISTINCT t.codigo_vendedor, t.nombres_vendedor, t.apellidos_vendedor, s.id_sucursal
    FROM tmp_ventas t
    JOIN sucursal s ON s.codigo = t.codigo_sucursal;
    SET v_resumen = CONCAT('vendedor=', ROW_COUNT());

    INSERT INTO cliente
        (nit, nombres, apellidos, genero, fecha_nacimiento, correo, telefono, direccion, id_municipio)
    SELECT DISTINCT
        t.nit_cliente, t.nombres_cliente, t.apellidos_cliente, t.genero_cliente,
        STR_TO_DATE(t.fecha_nacimiento_cliente, '%d/%m/%Y'),
        t.correo_cliente, t.telefono_cliente, t.direccion_cliente, m.id_municipio
    FROM tmp_ventas t
    JOIN departamento d ON d.nombre = t.departamento_cliente
    JOIN municipio m    ON m.nombre = t.municipio_cliente
                       AND m.id_departamento = d.id_departamento;
    SET v_resumen = CONCAT(v_resumen, '; cliente=', ROW_COUNT());

    INSERT INTO factura
        (numero, fecha, hora, id_sucursal, id_vendedor, id_cliente, id_metodo_pago, total, estado)
    SELECT
        t.numero_factura,
        STR_TO_DATE(t.fecha_venta, '%d/%m/%Y'),
        STR_TO_DATE(t.hora_venta, '%H:%i'),
        s.id_sucursal, v.id_vendedor, c.id_cliente, mp.id_metodo_pago,
        SUM(CAST(t.cantidad AS UNSIGNED) * CAST(t.precio_unitario AS DECIMAL(12,2))),
        'EMITIDA'
    FROM tmp_ventas t
    JOIN sucursal s     ON s.codigo = t.codigo_sucursal
    JOIN vendedor v     ON v.codigo = t.codigo_vendedor AND v.id_sucursal = s.id_sucursal
    JOIN cliente c      ON c.nit = t.nit_cliente
    JOIN metodo_pago mp ON mp.nombre = t.metodo_pago
    GROUP BY t.numero_factura,
             STR_TO_DATE(t.fecha_venta, '%d/%m/%Y'),
             STR_TO_DATE(t.hora_venta, '%H:%i'),
             s.id_sucursal, v.id_vendedor, c.id_cliente, mp.id_metodo_pago;
    SET v_resumen = CONCAT(v_resumen, '; factura=', ROW_COUNT());

    INSERT INTO detalle_factura (id_factura, id_producto, cantidad, precio_unitario, subtotal)
    SELECT f.id_factura, p.id_producto,
           CAST(t.cantidad AS UNSIGNED),
           CAST(t.precio_unitario AS DECIMAL(12,2)),
           CAST(t.cantidad AS UNSIGNED) * CAST(t.precio_unitario AS DECIMAL(12,2))
    FROM tmp_ventas t
    JOIN factura f  ON f.numero = t.numero_factura
    JOIN producto p ON p.codigo = t.codigo_producto;
    SET v_resumen = CONCAT(v_resumen, '; detalle_factura=', ROW_COUNT());

    COMMIT;

    INSERT INTO etl_control
        (fecha_inicio, fecha_fin, filas_leidas, filas_insertadas, estado, mensaje)
    VALUES
        (v_inicio, NOW(), v_filas, v_resumen, 'EXITOSO', NULL);

    SELECT 'ETL transaccional ejecutado correctamente' AS mensaje,
           v_filas AS filas_leidas, v_resumen AS filas_insertadas;
END //

DELIMITER ;

-- ---------- 4. Ejecución ----------
CALL sp_etl_cargar_datos();
CALL sp_etl_cargar_transaccional();

SELECT * FROM etl_control ORDER BY id_etl;

select *from municipio;
