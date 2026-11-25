/* =====================================================================
   02_etl_dw.sql
   sp_dw_cargar(): recarga COMPLETA de la estrella desde la base de la Fase 1.

   - Lee con INSERT INTO ... SELECT directamente de las tablas de la Fase 1
     (solo las consulta, no las modifica).
   - Reemplaza todo el contenido de la estrella: puede ejecutarse muchas
     veces y da el mismo resultado si los datos de origen no cambiaron.
     Las llaves sustitutas se asignan con ROW_NUMBER() para que sean iguales
     en cada recarga.
   - Conserva todas las lineas, incluidas las de facturas anuladas
     (columna vigente = 0).
   - Corre en UNA transaccion: si algo falla, ROLLBACK, la estrella queda
     intacta y se relanza el error. Se usa DELETE y no TRUNCATE porque
     TRUNCATE hace commit implicito y no se podria deshacer.
   - Cada ejecucion queda en dw_control; el registro de una ejecucion
     fallida se inserta DESPUES del ROLLBACK para que se conserve.

   El nombre de la base de la Fase 1 esta escrito como
   Proyecto_SistemasVentasGranilocas_V2. Si la suya se llama distinto, use
   Buscar y reemplazar en este archivo.
   ===================================================================== */
USE dw_ventas;

DROP PROCEDURE IF EXISTS sp_dw_cargar;
DELIMITER //

CREATE PROCEDURE sp_dw_cargar()
BEGIN
    DECLARE v_inicio    DATETIME DEFAULT NOW();
    DECLARE v_leidas    INT DEFAULT 0;
    DECLARE v_cargadas  INT DEFAULT 0;
    DECLARE v_mensaje   TEXT;

    -- Ante cualquier error: deshacer, registrar el fallo y relanzar el error
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_mensaje = MESSAGE_TEXT;
        ROLLBACK;

        INSERT INTO dw_control
            (fecha_inicio, fecha_fin, filas_leidas, filas_cargadas, estado, mensaje)
        VALUES
            (v_inicio, NOW(), v_leidas, 0, 'FALLIDO', v_mensaje);
        COMMIT;

        RESIGNAL;
    END;

    -- Lineas que hay en el origen (filas leidas)
    SELECT COUNT(*) INTO v_leidas
    FROM Proyecto_SistemasVentasGranilocas_V2.detalle_factura;

    START TRANSACTION;

    -- ---------------- 1. Vaciar la estrella (hechos primero) ----------------
    DELETE FROM fact_ventas;
    DELETE FROM dim_tiempo;
    DELETE FROM dim_producto;
    DELETE FROM dim_cliente;
    DELETE FROM dim_ubicacion;
    DELETE FROM dim_vendedor;
    DELETE FROM dim_metodo_pago;

    -- ---------------- 2. Dimensiones ----------------
    -- Tiempo: todas las fechas en que hay facturas
    INSERT INTO dim_tiempo
        (sk_tiempo, fecha, anio, trimestre, mes, nombre_mes, dia, dia_semana, anio_trimestre, anio_mes)
    SELECT ROW_NUMBER() OVER (ORDER BY x.fecha),
           x.fecha,
           YEAR(x.fecha),
           QUARTER(x.fecha),
           MONTH(x.fecha),
           ELT(MONTH(x.fecha), 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
                               'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'),
           DAY(x.fecha),
           ELT(WEEKDAY(x.fecha) + 1, 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'),
           CONCAT(YEAR(x.fecha), '-T', QUARTER(x.fecha)),
           DATE_FORMAT(x.fecha, '%Y-%m')
    FROM (SELECT DISTINCT fecha FROM Proyecto_SistemasVentasGranilocas_V2.factura) AS x;

    -- Producto (categoria y marca desnormalizadas)
    INSERT INTO dim_producto (sk_producto, codigo_producto, nombre_producto, categoria, marca)
    SELECT ROW_NUMBER() OVER (ORDER BY p.codigo),
           p.codigo, p.nombre, c.nombre, m.nombre
    FROM Proyecto_SistemasVentasGranilocas_V2.producto p
    JOIN Proyecto_SistemasVentasGranilocas_V2.categoria c ON c.id_categoria = p.id_categoria
    JOIN Proyecto_SistemasVentasGranilocas_V2.marca m     ON m.id_marca = p.id_marca;

    -- Cliente (municipio y departamento de su ficha)
    INSERT INTO dim_cliente (sk_cliente, nit, nombre_completo, genero, municipio, departamento)
    SELECT ROW_NUMBER() OVER (ORDER BY c.nit),
           c.nit, CONCAT(c.nombres, ' ', c.apellidos), c.genero, mu.nombre, d.nombre
    FROM Proyecto_SistemasVentasGranilocas_V2.cliente c
    JOIN Proyecto_SistemasVentasGranilocas_V2.municipio mu    ON mu.id_municipio = c.id_municipio
    JOIN Proyecto_SistemasVentasGranilocas_V2.departamento d  ON d.id_departamento = mu.id_departamento;

    -- Ubicacion (sucursal, con su municipio y departamento)
    INSERT INTO dim_ubicacion (sk_ubicacion, codigo_sucursal, nombre_sucursal, municipio, departamento)
    SELECT ROW_NUMBER() OVER (ORDER BY s.codigo),
           s.codigo, s.nombre, mu.nombre, d.nombre
    FROM Proyecto_SistemasVentasGranilocas_V2.sucursal s
    JOIN Proyecto_SistemasVentasGranilocas_V2.municipio mu    ON mu.id_municipio = s.id_municipio
    JOIN Proyecto_SistemasVentasGranilocas_V2.departamento d  ON d.id_departamento = mu.id_departamento;

    -- Vendedor (con la sucursal a la que pertenece)
    INSERT INTO dim_vendedor (sk_vendedor, codigo_vendedor, nombre_completo, codigo_sucursal, nombre_sucursal)
    SELECT ROW_NUMBER() OVER (ORDER BY v.codigo),
           v.codigo, CONCAT(v.nombres, ' ', v.apellidos), s.codigo, s.nombre
    FROM Proyecto_SistemasVentasGranilocas_V2.vendedor v
    JOIN Proyecto_SistemasVentasGranilocas_V2.sucursal s ON s.id_sucursal = v.id_sucursal;

    -- Metodo de pago
    INSERT INTO dim_metodo_pago (sk_metodo_pago, nombre_metodo)
    SELECT ROW_NUMBER() OVER (ORDER BY mp.nombre), mp.nombre
    FROM Proyecto_SistemasVentasGranilocas_V2.metodo_pago mp;

    -- ---------------- 3. Hechos: una fila por linea de factura ----------------
    INSERT INTO fact_ventas
        (sk_tiempo, sk_producto, sk_cliente, sk_ubicacion, sk_vendedor, sk_metodo_pago,
         numero_factura, linea, vigente, cantidad, precio_unitario, monto_linea)
    SELECT t.sk_tiempo, dp.sk_producto, dc.sk_cliente, du.sk_ubicacion, dv.sk_vendedor, dm.sk_metodo_pago,
           f.numero,
           ROW_NUMBER() OVER (PARTITION BY d.id_factura ORDER BY d.id_detalle),
           IF(f.estado = 'EMITIDA', 1, 0),
           d.cantidad, d.precio_unitario, d.subtotal
    FROM Proyecto_SistemasVentasGranilocas_V2.detalle_factura d
    JOIN Proyecto_SistemasVentasGranilocas_V2.factura f       ON f.id_factura = d.id_factura
    JOIN Proyecto_SistemasVentasGranilocas_V2.producto p      ON p.id_producto = d.id_producto
    JOIN Proyecto_SistemasVentasGranilocas_V2.cliente c       ON c.id_cliente = f.id_cliente
    JOIN Proyecto_SistemasVentasGranilocas_V2.sucursal s      ON s.id_sucursal = f.id_sucursal
    JOIN Proyecto_SistemasVentasGranilocas_V2.vendedor v      ON v.id_vendedor = f.id_vendedor
    JOIN Proyecto_SistemasVentasGranilocas_V2.metodo_pago mp  ON mp.id_metodo_pago = f.id_metodo_pago
    JOIN dim_tiempo t        ON t.fecha = f.fecha
    JOIN dim_producto dp     ON dp.codigo_producto = p.codigo
    JOIN dim_cliente dc      ON dc.nit = c.nit
    JOIN dim_ubicacion du    ON du.codigo_sucursal = s.codigo
    JOIN dim_vendedor dv     ON dv.codigo_vendedor = v.codigo
    JOIN dim_metodo_pago dm  ON dm.nombre_metodo = mp.nombre;

    SET v_cargadas = ROW_COUNT();

    -- Control: no puede perderse ninguna linea en el camino
    IF v_cargadas <> v_leidas THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-DW-01] Las filas cargadas en fact_ventas no coinciden con las lineas del origen.';
    END IF;

    COMMIT;

    -- ---------------- 4. Registro de la ejecucion exitosa ----------------
    INSERT INTO dw_control
        (fecha_inicio, fecha_fin, filas_leidas, filas_cargadas, estado, mensaje)
    VALUES
        (v_inicio, NOW(), v_leidas, v_cargadas, 'EXITOSO', NULL);

    SELECT 'Carga del datawarehouse realizada correctamente.' AS mensaje,
           v_leidas AS filas_leidas, v_cargadas AS filas_cargadas;
END //

DELIMITER ;

-- Ejecucion
CALL sp_dw_cargar();

SELECT * FROM dw_control ORDER BY id_control;
