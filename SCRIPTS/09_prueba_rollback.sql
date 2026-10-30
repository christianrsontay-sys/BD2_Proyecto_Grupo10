-- ##### ARCHIVO: 09_prueba_rollback.sql #####
/* =====================================================================
   09_prueba_rollback.sql
   Demuestra el control explícito de transacciones con un fallo FORZADO
   a mitad de camino: el procedimiento de demostración inserta una factura
   y su línea y luego lanza un error a propósito. El ROLLBACK debe deshacer
   TODO (factura, detalle y los registros que los triggers escribieron en
   la bitácora).

   Requiere haber ejecutado antes 07_pruebas.sql (usa el vendedor TSTV01
   y el cliente 9900001-1 creados allí).

   Como el CALL termina en error, en Workbench ejecute el script con
   "Stop Script Execution on Errors" desmarcado, o por bloques.
   ===================================================================== */
USE Proyecto_SistemasVentasGranilocas_V2;

DROP PROCEDURE IF EXISTS sp_demo_rollback_venta;
DELIMITER //

CREATE PROCEDURE sp_demo_rollback_venta(
    IN p_codigo_vendedor VARCHAR(20),
    IN p_nit_cliente     VARCHAR(50),
    IN p_codigo_producto VARCHAR(20)
)
BEGIN
    DECLARE v_id_sucursal INT;
    DECLARE v_id_vendedor INT;
    DECLARE v_id_cliente  INT;
    DECLARE v_id_producto INT;
    DECLARE v_precio      DECIMAL(12,2);
    DECLARE v_id_factura  INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT id_vendedor, id_sucursal INTO v_id_vendedor, v_id_sucursal
    FROM vendedor WHERE codigo = p_codigo_vendedor;
    SELECT id_cliente INTO v_id_cliente FROM cliente WHERE nit = p_nit_cliente;
    SELECT id_producto, precio_actual INTO v_id_producto, v_precio
    FROM producto WHERE codigo = p_codigo_producto;

    START TRANSACTION;

    INSERT INTO factura (numero, fecha, hora, id_sucursal, id_vendedor, id_cliente, id_metodo_pago, total)
    VALUES ('999999', CURDATE(), CURTIME(), v_id_sucursal, v_id_vendedor, v_id_cliente, 1, v_precio);
    SET v_id_factura = LAST_INSERT_ID();

    INSERT INTO detalle_factura (id_factura, id_producto, cantidad, precio_unitario, subtotal)
    VALUES (v_id_factura, v_id_producto, 1, v_precio, v_precio);

    -- Fallo simulado DESPUÉS de haber insertado: el handler debe deshacer todo
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '[E-DEMO-01] Fallo simulado a mitad de la transacción.';

    COMMIT;   -- nunca se alcanza
END //

DELIMITER ;

-- Conteos ANTES
SET @fact_antes = (SELECT COUNT(*) FROM factura);
SET @det_antes  = (SELECT COUNT(*) FROM detalle_factura);
SET @bit_antes  = (SELECT COUNT(*) FROM bitacora);
SET @prod_demo  = (SELECT codigo FROM producto WHERE codigo = 'TSTP01');

-- Esperado: [E-DEMO-01] Fallo simulado a mitad de la transacción.
CALL sp_demo_rollback_venta('TSTV01', '9900001-1', @prod_demo);

-- Conteos DESPUÉS: deben ser idénticos a los de antes
SELECT @fact_antes AS facturas_antes, (SELECT COUNT(*) FROM factura)         AS facturas_despues,
       @det_antes  AS detalle_antes,  (SELECT COUNT(*) FROM detalle_factura) AS detalle_despues,
       @bit_antes  AS bitacora_antes, (SELECT COUNT(*) FROM bitacora)        AS bitacora_despues;

SELECT CASE
         WHEN @fact_antes = (SELECT COUNT(*) FROM factura)
          AND @det_antes  = (SELECT COUNT(*) FROM detalle_factura)
          AND @bit_antes  = (SELECT COUNT(*) FROM bitacora)
         THEN 'CORRECTO: el ROLLBACK deshizo todo'
         ELSE 'FALLA: quedaron cambios a medias'
       END AS prueba_rollback;

-- La factura de demostración no debe existir (esperado: 0)
SELECT COUNT(*) AS factura_999999_existe FROM factura WHERE numero = '999999';

-- Se elimina el procedimiento de demostración (no forma parte del sistema)
DROP PROCEDURE IF EXISTS sp_demo_rollback_venta;