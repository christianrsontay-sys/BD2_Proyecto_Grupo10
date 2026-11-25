/* =====================================================================
   03_validacion_dw.sql
   Muestra que la estrella cuadra con la base de la Fase 1:
   cantidad de lineas, de facturas y monto total, al centavo.
   Columna estado: OK = coincide, REVISAR = hay diferencia.

   Con el archivo de practica deben salir:
     20000 lineas, 7665 facturas y 1,909,480.75 de monto total.
   (El nombre de la base de la Fase 1 es Proyecto_SistemasVentasGranilocas_V2;
    si la suya se llama distinto, use Buscar y reemplazar.)
   ===================================================================== */
USE dw_ventas;

-- 1. CONTROLES PRINCIPALES: lineas, facturas y monto total
SELECT control, fase1, estrella, IF(fase1 = estrella, 'OK', 'REVISAR') AS estado
FROM (
    SELECT 'lineas (todas)' AS control,
           (SELECT COUNT(*) FROM Proyecto_SistemasVentasGranilocas_V2.detalle_factura) AS fase1,
           (SELECT COUNT(*) FROM fact_ventas) AS estrella
    UNION ALL
    SELECT 'facturas (todas)',
           (SELECT COUNT(*) FROM Proyecto_SistemasVentasGranilocas_V2.factura),
           (SELECT COUNT(DISTINCT numero_factura) FROM fact_ventas)
    UNION ALL
    SELECT 'monto total (todas las lineas)',
           (SELECT COALESCE(SUM(subtotal), 0) FROM Proyecto_SistemasVentasGranilocas_V2.detalle_factura),
           (SELECT COALESCE(SUM(monto_linea), 0) FROM fact_ventas)
    UNION ALL
    SELECT 'facturas vigentes',
           (SELECT COUNT(*) FROM Proyecto_SistemasVentasGranilocas_V2.factura WHERE estado = 'EMITIDA'),
           (SELECT COUNT(DISTINCT numero_factura) FROM fact_ventas WHERE vigente = 1)
    UNION ALL
    SELECT 'monto de facturas vigentes',
           (SELECT COALESCE(SUM(total), 0) FROM Proyecto_SistemasVentasGranilocas_V2.factura WHERE estado = 'EMITIDA'),
           (SELECT COALESCE(SUM(monto_linea), 0) FROM fact_ventas WHERE vigente = 1)
    UNION ALL
    SELECT 'facturas anuladas',
           (SELECT COUNT(*) FROM Proyecto_SistemasVentasGranilocas_V2.factura WHERE estado = 'ANULADA'),
           (SELECT COUNT(DISTINCT numero_factura) FROM fact_ventas WHERE vigente = 0)
    UNION ALL
    SELECT 'monto de facturas anuladas',
           (SELECT COALESCE(SUM(total), 0) FROM Proyecto_SistemasVentasGranilocas_V2.factura WHERE estado = 'ANULADA'),
           (SELECT COALESCE(SUM(monto_linea), 0) FROM fact_ventas WHERE vigente = 0)
) AS controles;

-- 2. DIMENSIONES: mismas filas que el origen
SELECT control, fase1, estrella, IF(fase1 = estrella, 'OK', 'REVISAR') AS estado
FROM (
    SELECT 'dim_producto' AS control,
           (SELECT COUNT(*) FROM Proyecto_SistemasVentasGranilocas_V2.producto) AS fase1,
           (SELECT COUNT(*) FROM dim_producto) AS estrella
    UNION ALL SELECT 'dim_cliente',
           (SELECT COUNT(*) FROM Proyecto_SistemasVentasGranilocas_V2.cliente),
           (SELECT COUNT(*) FROM dim_cliente)
    UNION ALL SELECT 'dim_ubicacion',
           (SELECT COUNT(*) FROM Proyecto_SistemasVentasGranilocas_V2.sucursal),
           (SELECT COUNT(*) FROM dim_ubicacion)
    UNION ALL SELECT 'dim_vendedor',
           (SELECT COUNT(*) FROM Proyecto_SistemasVentasGranilocas_V2.vendedor),
           (SELECT COUNT(*) FROM dim_vendedor)
    UNION ALL SELECT 'dim_metodo_pago',
           (SELECT COUNT(*) FROM Proyecto_SistemasVentasGranilocas_V2.metodo_pago),
           (SELECT COUNT(*) FROM dim_metodo_pago)
    UNION ALL SELECT 'dim_tiempo (fechas distintas)',
           (SELECT COUNT(DISTINCT fecha) FROM Proyecto_SistemasVentasGranilocas_V2.factura),
           (SELECT COUNT(*) FROM dim_tiempo)
) AS dimensiones;

-- 3. MONTO TOTAL POR ANIO: Fase 1 contra estrella (todas las lineas)
SELECT o.anio, o.monto_fase1, e.monto_estrella,
       IF(o.monto_fase1 = e.monto_estrella, 'OK', 'REVISAR') AS estado
FROM (SELECT YEAR(f.fecha) AS anio, SUM(d.subtotal) AS monto_fase1
      FROM Proyecto_SistemasVentasGranilocas_V2.detalle_factura d
      JOIN Proyecto_SistemasVentasGranilocas_V2.factura f ON f.id_factura = d.id_factura
      GROUP BY YEAR(f.fecha)) o
JOIN (SELECT t.anio, SUM(h.monto_linea) AS monto_estrella
      FROM fact_ventas h JOIN dim_tiempo t ON t.sk_tiempo = h.sk_tiempo
      GROUP BY t.anio) e ON e.anio = o.anio
ORDER BY o.anio;

-- 4. FECHAS: toda fecha de factura esta en dim_tiempo (debe dar 0 filas)
SELECT DISTINCT f.fecha
FROM Proyecto_SistemasVentasGranilocas_V2.factura f
LEFT JOIN dim_tiempo t ON t.fecha = f.fecha
WHERE t.sk_tiempo IS NULL;

-- 5. FACTURAS CUYO MONTO EN LA ESTRELLA DIFIERE DE SU TOTAL EN LA FASE 1 (debe dar 0 filas)
SELECT f.numero, f.total AS total_fase1, h.monto AS monto_estrella
FROM Proyecto_SistemasVentasGranilocas_V2.factura f
JOIN (SELECT numero_factura, SUM(monto_linea) AS monto
      FROM fact_ventas GROUP BY numero_factura) h ON h.numero_factura = f.numero
WHERE f.total <> h.monto;

-- 6. ULTIMAS EJECUCIONES DE LA CARGA
SELECT * FROM dw_control ORDER BY id_control DESC LIMIT 5;
