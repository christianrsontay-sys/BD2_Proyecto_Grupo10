-- ##### ARCHIVO: 08_validacion_etl.sql #####
/* =====================================================================
   08_validacion_etl.sql
   Comprueba que la migración cuadra con el CSV. Está escrita para dar el
   mismo resultado aunque ya se hayan ejecutado las pruebas del script 07
   (compara solo contra los registros que vienen del CSV).
   Columna estado: OK = coincide, REVISAR = hay diferencia.
   ===================================================================== */
USE Proyecto_SistemasVentasGranilocas_V2;

-- 1. Conteos: lo que trae el CSV contra lo cargado
SELECT entidad, esperado, cargado, IF(esperado = cargado, 'OK', 'REVISAR') AS estado
FROM (
    SELECT 'departamento' AS entidad,
           (SELECT COUNT(*) FROM (SELECT departamento_sucursal AS d FROM tmp_ventas
                                  UNION SELECT departamento_cliente FROM tmp_ventas) x) AS esperado,
           (SELECT COUNT(*) FROM departamento) AS cargado
    UNION ALL
    SELECT 'municipio',
           (SELECT COUNT(*) FROM (SELECT municipio_sucursal, departamento_sucursal FROM tmp_ventas
                                  UNION SELECT municipio_cliente, departamento_cliente FROM tmp_ventas) x),
           (SELECT COUNT(*) FROM municipio)
    UNION ALL
    SELECT 'sucursal',
           (SELECT COUNT(DISTINCT codigo_sucursal) FROM tmp_ventas),
           (SELECT COUNT(*) FROM sucursal)
    UNION ALL
    SELECT 'categoria',
           (SELECT COUNT(DISTINCT categoria) FROM tmp_ventas),
           (SELECT COUNT(*) FROM categoria)
    UNION ALL
    SELECT 'marca',
           (SELECT COUNT(DISTINCT marca) FROM tmp_ventas),
           (SELECT COUNT(*) FROM marca)
    UNION ALL
    SELECT 'producto',
           (SELECT COUNT(DISTINCT codigo_producto) FROM tmp_ventas),
           (SELECT COUNT(*) FROM producto WHERE codigo IN (SELECT codigo_producto FROM tmp_ventas))
    UNION ALL
    SELECT 'vendedor',
           (SELECT COUNT(DISTINCT codigo_vendedor) FROM tmp_ventas),
           (SELECT COUNT(*) FROM vendedor WHERE codigo IN (SELECT codigo_vendedor FROM tmp_ventas))
    UNION ALL
    SELECT 'cliente',
           (SELECT COUNT(DISTINCT nit_cliente) FROM tmp_ventas),
           (SELECT COUNT(*) FROM cliente WHERE nit IN (SELECT nit_cliente FROM tmp_ventas))
    UNION ALL
    SELECT 'factura',
           (SELECT COUNT(DISTINCT numero_factura) FROM tmp_ventas),
           (SELECT COUNT(*) FROM factura WHERE numero IN (SELECT numero_factura FROM tmp_ventas))
    UNION ALL
    SELECT 'detalle_factura',
           (SELECT COUNT(*) FROM tmp_ventas),
           (SELECT COUNT(*) FROM detalle_factura
            WHERE id_factura IN (SELECT id_factura FROM factura
                                 WHERE numero IN (SELECT numero_factura FROM tmp_ventas)))
) AS resumen;

-- 2. Total de ventas: CSV contra base de datos
SELECT
    (SELECT SUM(CAST(subtotal AS DECIMAL(12,2))) FROM tmp_ventas) AS total_csv,
    (SELECT SUM(total) FROM factura
     WHERE numero IN (SELECT numero_factura FROM tmp_ventas))     AS total_bd,
    IF((SELECT SUM(CAST(subtotal AS DECIMAL(12,2))) FROM tmp_ventas) =
       (SELECT SUM(total) FROM factura WHERE numero IN (SELECT numero_factura FROM tmp_ventas)),
       'OK', 'REVISAR') AS estado;

-- 3. Ventas por año (para comparar con el Excel original)
SELECT YEAR(fecha) AS anio, COUNT(*) AS facturas, SUM(total) AS total_ventas
FROM factura
WHERE numero IN (SELECT numero_factura FROM tmp_ventas)
GROUP BY YEAR(fecha)
ORDER BY anio;

-- 4. Facturas cuyo total no es la suma de su detalle (debe dar 0 filas)
SELECT f.numero, f.total, fn_total_factura(f.id_factura) AS suma_detalle
FROM factura f
WHERE f.total <> fn_total_factura(f.id_factura);

-- 5. Facturas sin ninguna línea (debe dar 0 filas)
SELECT f.numero
FROM factura f
LEFT JOIN detalle_factura d ON d.id_factura = f.id_factura
WHERE d.id_detalle IS NULL;

-- 6. Diferencias de precio actual (08): ventas de 2025 con precio distinto al actual (debe dar 0 filas)
SELECT p.codigo, p.nombre, p.precio_actual, d.precio_unitario AS precio_venta, f.fecha
FROM detalle_factura d
JOIN factura  f ON f.id_factura  = d.id_factura
JOIN producto p ON p.id_producto = d.id_producto
WHERE YEAR(f.fecha) = 2025
  AND p.codigo IN (SELECT codigo_producto FROM tmp_ventas)
  AND d.precio_unitario <> p.precio_actual;

-- 7. Clientes con NIT o correo inválido según las funciones (debe dar 0 filas)
SELECT id_cliente, nit, correo
FROM cliente
WHERE fn_validar_nit(nit) = 0 OR fn_validar_correo(correo) = 0;

-- 8. Facturas hechas por un vendedor fuera de su sucursal (debe dar 0 filas)
SELECT f.numero, f.id_sucursal AS sucursal_factura, v.id_sucursal AS sucursal_vendedor
FROM factura f
JOIN vendedor v ON v.id_vendedor = f.id_vendedor
WHERE f.id_sucursal <> v.id_sucursal;

-- 9. Bitácora de ejecuciones del ETL
SELECT * FROM etl_control ORDER BY id_etl;