-- ##### ARCHIVO: 07_pruebas.sql #####
/* =====================================================================
   07_pruebas.sql
   Demuestra el funcionamiento de la solución usando ÚNICAMENTE los
   procedimientos almacenados (CALL) y consultas SELECT de verificación.
   La única excepción son los DELETE/UPDATE directos de la sección
   "TRIGGERS DE REGLAS DE NEGOCIO", que se intentan a propósito para
   demostrar que los triggers bloquean la operación.

   DATOS INDEPENDIENTES DEL ARCHIVO CARGADO
   El script crea con procedimientos todo lo que usa: clientes (NIT
   9900001-1 y 9900002-2), vendedores (TSTV01, TSTV02) y productos
   (TSTP01, TSTP02). Lo único que toma de la base son datos que existen
   igual en cualquier archivo: sucursales SUC01 y SUC02, y un municipio,
   una categoría y una marca (los busca dinámicamente). El número de
   factura nunca se escribe a mano: es el que devuelve sp_venta_registrar
   (queda en la variable @numero_factura_generado).

   CÓMO EJECUTARLO EN WORKBENCH
   Los casos de ERROR detienen el script en ese punto. Opciones:
     a) Query > desmarcar "Stop Script Execution on Errors", y ejecutar todo; o
     b) seleccionar y ejecutar cada caso por separado (Ctrl+Shift+Enter).
   Las variables @... viven durante la sesión: ejecute siempre primero el
   bloque "DATOS DE REFERENCIA" en la misma pestaña.

   Se ejecuta UNA vez por base (crea datos de prueba con códigos fijos).
   ===================================================================== */
USE Proyecto_SistemasVentasGranilocas_V2;


-- =====================================================================
-- DATOS DE REFERENCIA
-- @bit_inicio marca hasta dónde llegaba la bitácora antes de las pruebas,
-- para mostrar al final solo lo que generaron las pruebas.
-- =====================================================================
SELECT COUNT(*) AS filas_en_bitacora_antes_de_las_pruebas FROM bitacora;   -- informativo
SET @bit_inicio = (SELECT COALESCE(MAX(id_bitacora), 0) FROM bitacora);

SET @suc   = 'SUC01';
SET @suc2  = 'SUC02';   -- otra sucursal distinta (sirve para probar la regla 3)
SET @muni  = (SELECT nombre FROM municipio ORDER BY id_municipio LIMIT 1);
SET @cat   = (SELECT nombre FROM categoria ORDER BY id_categoria LIMIT 1);
SET @marca = (SELECT nombre FROM marca ORDER BY id_marca LIMIT 1);

SELECT @suc AS sucursal, @suc2 AS otra_sucursal, @muni AS municipio,
       @cat AS categoria, @marca AS marca;
-- esperado: SUC01, SUC02 y los demás con valor (ninguno NULL)

-- Detalles de venta (arreglos JSON) para los distintos casos
SET @det_a      = '[{"codigo_producto":"TSTP01","cantidad":3},{"codigo_producto":"TSTP02","cantidad":2}]';
SET @det_b      = '[{"codigo_producto":"TSTP02","cantidad":1}]';
SET @det_neg    = '[{"codigo_producto":"TSTP01","cantidad":-1}]';
SET @det_dup    = '[{"codigo_producto":"TSTP01","cantidad":1},{"codigo_producto":"TSTP01","cantidad":2}]';
SET @det_noex   = '[{"codigo_producto":"TSTP01","cantidad":1},{"codigo_producto":"NOEXISTE9","cantidad":1}]';
SET @det_inact  = '[{"codigo_producto":"TSTP02","cantidad":1}]';
SET @det_vacio  = '[]';


-- =====================================================================
-- FUNCIONES
-- =====================================================================
SELECT fn_validar_nit('12345678')   AS nit_solo_digitos,     -- esperado: 1
       fn_validar_nit('1234567-8')  AS nit_con_guion,        -- esperado: 1
       fn_validar_nit('1234567-89') AS nit_dos_digitos,      -- esperado: 0
       fn_validar_nit('ABC123')     AS nit_con_letras,       -- esperado: 0
       fn_validar_nit(NULL)         AS nit_nulo;             -- esperado: 0

SELECT fn_validar_correo('ana@correo.com') AS correo_valido,      -- esperado: 1
       fn_validar_correo('ana@correo')     AS correo_sin_ext,     -- esperado: 0
       fn_validar_correo('ana correo.com') AS correo_con_espacio; -- esperado: 0

SELECT fn_descripcion_bitacora('factura', 'ANULAR', '107666. Motivo: error en el cliente') AS descripcion;
-- esperado: Se anuló la factura 107666. Motivo: error en el cliente


-- =====================================================================
-- 1. sp_cliente_crear
-- =====================================================================

-- Caso 1 (ÉXITO): cliente nuevo con todos los datos válidos.
-- Esperado: "Cliente con NIT 9900001-1 registrado correctamente." y su id.
CALL sp_cliente_crear('9900001-1', 'Laura', 'Mendoza', 'F', '1990-05-20', '55550001',
                      'laura.test@pruebas.com', '5a Avenida 10-20 Zona 1', @muni);

-- Caso 2 (ÉXITO): segundo cliente, que se usará más adelante para la baja lógica.
CALL sp_cliente_crear('9900002-2', 'Carlos', 'Ruiz', 'M', '1979-11-02', '55550002',
                      'carlos.test@pruebas.com', 'Calle 2 Zona 1', @muni);

-- Caso 3 (ERROR): NIT con formato inválido.
-- Esperado: [E-CLI-01] El NIT es inválido...
CALL sp_cliente_crear('12AB', 'Pedro', 'Gomez', 'M', '1985-01-10', '55550003',
                      'pedro.test@pruebas.com', 'Calle 1', @muni);

-- Caso 4 (ERROR): nombres con caracteres no permitidos.
-- Esperado: [E-CLI-02] Los nombres o apellidos están vacíos o tienen caracteres no permitidos.
CALL sp_cliente_crear('9900003-3', 'Pedro@#', 'Gomez', 'M', '1985-01-10', '55550003',
                      'pedro.test@pruebas.com', 'Calle 1', @muni);

-- Caso 5 (ERROR): género distinto de M o F.
-- Esperado: [E-CLI-03] El género debe ser M o F.
CALL sp_cliente_crear('9900003-3', 'Pedro', 'Gomez', 'X', '1985-01-10', '55550003',
                      'pedro.test@pruebas.com', 'Calle 1', @muni);

-- Caso 6 (ERROR): fecha de nacimiento futura.
-- Esperado: [E-CLI-04] La fecha de nacimiento es obligatoria y no puede ser futura.
CALL sp_cliente_crear('9900003-3', 'Pedro', 'Gomez', 'M', '2999-01-01', '55550003',
                      'pedro.test@pruebas.com', 'Calle 1', @muni);

-- Caso 7 (ERROR): teléfono que no tiene 8 dígitos.
-- Esperado: [E-CLI-12] El teléfono debe tener exactamente 8 dígitos.
CALL sp_cliente_crear('9900003-3', 'Pedro', 'Gomez', 'M', '1985-01-10', '5555',
                      'pedro.test@pruebas.com', 'Calle 1', @muni);

-- Caso 8 (ERROR): correo con formato inválido.
-- Esperado: [E-CLI-05] El correo electrónico tiene un formato inválido.
CALL sp_cliente_crear('9900003-3', 'Pedro', 'Gomez', 'M', '1985-01-10', '55550003',
                      'correo-mal-escrito', 'Calle 1', @muni);

-- Caso 9 (ERROR): NIT que ya existe (regla 4).
-- Esperado: [E-CLI-06] Ya existe un cliente con el NIT 9900001-1.
CALL sp_cliente_crear('9900001-1', 'Otro', 'Cliente', 'M', '1985-01-10', '55550003',
                      'otro.test@pruebas.com', 'Calle 1', @muni);

-- Caso 10 (ERROR): correo que ya existe (regla 4).
-- Esperado: [E-CLI-07] Ya existe un cliente con el correo laura.test@pruebas.com.
CALL sp_cliente_crear('9900003-3', 'Pedro', 'Gomez', 'M', '1985-01-10', '55550003',
                      'laura.test@pruebas.com', 'Calle 1', @muni);

-- Caso 11 (ERROR): municipio que no existe.
-- Esperado: [E-CLI-08] El municipio indicado no existe.
CALL sp_cliente_crear('9900003-3', 'Pedro', 'Gomez', 'M', '1985-01-10', '55550003',
                      'pedro.test@pruebas.com', 'Calle 1', 'Municipio Fantasma');


-- =====================================================================
-- 9. sp_vendedor_crear
-- =====================================================================

-- Caso 1 (ÉXITO): vendedor asignado a una sola sucursal (regla 3).
-- Esperado: "Vendedor TSTV01 registrado correctamente."
CALL sp_vendedor_crear('TSTV01', 'Mario', 'Castillo', @suc);

-- Caso 2 (ÉXITO): segundo vendedor, en OTRA sucursal (sirve para probar la regla 3).
CALL sp_vendedor_crear('TSTV02', 'Ana', 'Morales', @suc2);

-- Caso 3 (ERROR): código que ya existe.
-- Esperado: [E-VEN-03] Ya existe un vendedor con el código TSTV01.
CALL sp_vendedor_crear('TSTV01', 'Mario', 'Castillo', @suc);

-- Caso 4 (ERROR): sucursal inexistente.
-- Esperado: [E-VEN-04] La sucursal indicada no existe.
CALL sp_vendedor_crear('TSTV03', 'Mario', 'Castillo', 'SUC99');

-- Caso 5 (ERROR): nombres vacíos.
-- Esperado: [E-VEN-02] Los nombres o apellidos están vacíos o tienen caracteres no permitidos.
CALL sp_vendedor_crear('TSTV03', '   ', 'Castillo', @suc);


-- =====================================================================
-- 5. sp_producto_crear
-- =====================================================================

-- Caso 1 (ÉXITO): producto con categoría y marca existentes.
-- Esperado: "Producto TSTP01 registrado correctamente." y su id.
CALL sp_producto_crear('TSTP01', 'Producto de prueba uno', @cat, @marca, 25.00);

-- Caso 2 (ÉXITO): segundo producto.
CALL sp_producto_crear('TSTP02', 'Producto de prueba dos', @cat, @marca, 10.00);

-- Caso 3 (ERROR): código que ya existe.
-- Esperado: [E-PRO-04] Ya existe un producto con el código TSTP01.
CALL sp_producto_crear('TSTP01', 'Producto repetido', @cat, @marca, 25.00);

-- Caso 4 (ERROR): precio negativo.
-- Esperado: [E-PRO-03] El precio debe ser mayor que cero.
CALL sp_producto_crear('TSTP03', 'Producto sin precio', @cat, @marca, -5.00);

-- Caso 5 (ERROR): categoría inexistente.
-- Esperado: [E-PRO-05] La categoría indicada no existe.
CALL sp_producto_crear('TSTP03', 'Producto sin categoria', 'Categoria Fantasma', @marca, 10.00);

-- Caso 6 (ERROR): marca inexistente.
-- Esperado: [E-PRO-06] La marca indicada no existe.
CALL sp_producto_crear('TSTP03', 'Producto sin marca', @cat, 'Marca Fantasma', 10.00);

-- Caso 7 (ERROR): nombre vacío.
-- Esperado: [E-PRO-02] El nombre del producto está vacío o tiene caracteres no permitidos.
CALL sp_producto_crear('TSTP03', '   ', @cat, @marca, 10.00);


-- =====================================================================
-- 10. sp_venta_registrar  (procedimiento transaccional)
-- Parámetros: sucursal, vendedor, nit del cliente, método de pago, detalle (JSON)
-- =====================================================================

-- Caso 1 (ÉXITO): factura con 2 líneas: TSTP01 x3 a 25.00 y TSTP02 x2 a 10.00.
-- Esperado: "Factura <número> registrada correctamente." con total = 95.00.
CALL sp_venta_registrar(@suc, 'TSTV01', '9900001-1', 'Efectivo', @det_a);
SET @num_a    = @numero_factura_generado;      -- el número que devolvió sp_venta_registrar
SET @id_fac_a = (SELECT id_factura FROM factura WHERE numero = @num_a);

-- Verificación: el total guardado es la suma de su detalle (regla 8). Esperado: 95.00, OK.
SELECT f.numero, f.total AS total_cabecera, fn_total_factura(f.id_factura) AS suma_detalle,
       IF(f.total = fn_total_factura(f.id_factura) AND f.total = 95.00, 'OK', 'REVISAR') AS estado
FROM factura f WHERE f.id_factura = @id_fac_a;

-- Caso 2 (ÉXITO): segunda factura, con tarjeta (se anulará más adelante). Total = 10.00.
CALL sp_venta_registrar(@suc, 'TSTV01', '9900001-1', 'Tarjeta', @det_b);
SET @num_b    = @numero_factura_generado;      -- el número que devolvió sp_venta_registrar
SET @id_fac_b = (SELECT id_factura FROM factura WHERE numero = @num_b);

-- Caso 3 (ERROR): el vendedor no pertenece a esa sucursal (regla 3).
-- Esperado: [E-VTA-05] El vendedor TSTV02 no pertenece a la sucursal ...
CALL sp_venta_registrar(@suc, 'TSTV02', '9900001-1', 'Efectivo', @det_a);

-- Caso 4 (ERROR): vendedor inexistente.
-- Esperado: [E-VTA-02] No existe el vendedor NOEXISTE.
CALL sp_venta_registrar(@suc, 'NOEXISTE', '9900001-1', 'Efectivo', @det_a);

-- Caso 5 (ERROR): sucursal inexistente.
-- Esperado: [E-VTA-04] La sucursal indicada no existe.
CALL sp_venta_registrar('SUC99', 'TSTV01', '9900001-1', 'Efectivo', @det_a);

-- Caso 6 (ERROR): cliente inexistente.
-- Esperado: [E-VTA-06] No existe un cliente con el NIT 8888888-8.
CALL sp_venta_registrar(@suc, 'TSTV01', '8888888-8', 'Efectivo', @det_a);

-- Caso 7 (ERROR): método de pago que no es Efectivo, Tarjeta ni Transferencia.
-- Esperado: [E-VTA-08] El método de pago debe ser Efectivo, Tarjeta o Transferencia.
CALL sp_venta_registrar(@suc, 'TSTV01', '9900001-1', 'Cheque', @det_a);

-- Caso 8 (ERROR): cantidad negativa.
-- Esperado: [E-VTA-09] Cada línea necesita un código y una cantidad entera mayor que cero.
CALL sp_venta_registrar(@suc, 'TSTV01', '9900001-1', 'Efectivo', @det_neg);

-- Caso 9 (ERROR): el mismo producto en dos líneas (regla 2).
-- Esperado: [E-VTA-10] Un producto no puede repetirse en la misma factura.
CALL sp_venta_registrar(@suc, 'TSTV01', '9900001-1', 'Efectivo', @det_dup);

-- Caso 10 (ERROR): detalle vacío.
-- Esperado: [E-VTA-01] El detalle debe enviarse como un arreglo JSON válido con al menos una línea.
CALL sp_venta_registrar(@suc, 'TSTV01', '9900001-1', 'Efectivo', @det_vacio);


-- =====================================================================
-- 12. sp_venta_consultar
-- =====================================================================

-- Caso 1 (ÉXITO): devuelve el encabezado y, en una segunda pestaña, las 2 líneas.
-- Esperado: estado EMITIDA, total 95.00 (calculado con fn_total_factura).
CALL sp_venta_consultar(@num_a);

-- Caso 2 (ERROR): factura inexistente.
-- Esperado: [E-VTA-14] No existe la factura 1.
CALL sp_venta_consultar('1');

-- Caso 3 (ERROR): número de factura vacío.
-- Esperado: [E-VTA-17] El número de factura es obligatorio.
CALL sp_venta_consultar(NULL);


-- =====================================================================
-- 6. sp_producto_actualizar
-- Las ventas históricas no se alteran (regla 6).
-- =====================================================================

-- Caso 1 (ÉXITO): cambiar nombre y subir el precio de 25.00 a 45.00.
-- Esperado: precio_anterior = 25.00, precio_nuevo = 45.00.
CALL sp_producto_actualizar('TSTP01', 'Producto de prueba uno plus', 45.00);

-- Verificación de la regla 6: la factura ya emitida conserva el precio de venta.
-- Esperado: precio_vendido = 25.00 y precio_actual = 45.00.
SELECT p.codigo, d.precio_unitario AS precio_vendido, p.precio_actual
FROM detalle_factura d
JOIN producto p ON p.id_producto = d.id_producto
WHERE d.id_factura = @id_fac_a AND p.codigo = 'TSTP01';

-- Caso 2 (ERROR): precio cero.
-- Esperado: [E-PRO-03] El precio debe ser mayor que cero.
CALL sp_producto_actualizar('TSTP01', NULL, 0);

-- Caso 3 (ERROR): producto inexistente.
-- Esperado: [E-PRO-07] No existe un producto con el código NOEXISTE9.
CALL sp_producto_actualizar('NOEXISTE9', 'Nombre', 10.00);


-- =====================================================================
-- 2. sp_cliente_actualizar
-- (un parámetro en NULL significa "dejar el valor actual")
-- =====================================================================

-- Caso 1 (ÉXITO): cambiar teléfono y dirección con un solo UPDATE
-- (en el Excel original habría que modificar cientos de filas).
-- Esperado: "Cliente con NIT 9900001-1 actualizado correctamente."
CALL sp_cliente_actualizar('9900001-1', '55559999', NULL, 'Nueva dirección 3-45 Zona 2', NULL);

-- Verificación. Esperado: teléfono 55559999 y correo sin cambios (laura.test@pruebas.com).
SELECT nit, telefono, correo, direccion FROM cliente WHERE nit = '9900001-1';

-- Caso 2 (ERROR): cliente inexistente.
-- Esperado: [E-CLI-09] No existe un cliente con el NIT 8888888-8.
CALL sp_cliente_actualizar('8888888-8', '55559999', NULL, NULL, NULL);

-- Caso 3 (ERROR): el correo nuevo ya lo usa otro cliente.
-- Esperado: [E-CLI-07] Ya existe otro cliente con el correo carlos.test@pruebas.com.
CALL sp_cliente_actualizar('9900001-1', NULL, 'carlos.test@pruebas.com', NULL, NULL);

-- Caso 4 (ERROR): teléfono que no tiene 8 dígitos.
-- Esperado: [E-CLI-12] El teléfono debe tener exactamente 8 dígitos.
CALL sp_cliente_actualizar('9900001-1', 'abc', NULL, NULL, NULL);


-- =====================================================================
-- 11. sp_venta_anular  (procedimiento transaccional, regla 9)
-- =====================================================================

-- Caso 1 (ERROR): motivo vacío.
-- Esperado: [E-VTA-16] El motivo de anulación es obligatorio.
CALL sp_venta_anular(@num_a, '   ');

-- Caso 2 (ÉXITO): anular la segunda factura.
-- Esperado: "Factura <número> anulada correctamente."
CALL sp_venta_anular(@num_b, 'Error en el método de pago');

-- Verificación: la factura NO se borró; queda ANULADA con fecha y motivo.
SELECT numero, estado, fecha_anulacion, motivo_anulacion FROM factura WHERE numero = @num_b;

-- Caso 3 (ERROR): anular una factura que ya está anulada.
-- Esperado: [E-VTA-15] La factura ya estaba anulada.
CALL sp_venta_anular(@num_b, 'Segundo intento de anulación');

-- Caso 4 (ERROR): factura inexistente.
-- Esperado: [E-VTA-14] No existe la factura 1.
CALL sp_venta_anular('1', 'No existe esta factura');

-- Consultar una factura anulada (ÉXITO). Esperado: estado ANULADA y su motivo.
CALL sp_venta_consultar(@num_b);


-- =====================================================================
-- 4. sp_cliente_consultar
-- =====================================================================

-- Caso 1 (ÉXITO): datos, municipio, departamento, compras vigentes y monto total.
-- Esperado: compras_vigentes = 1 (la factura anulada no cuenta) y monto_total_comprado = 95.00.
CALL sp_cliente_consultar('9900001-1');

-- Caso 2 (ERROR): cliente inexistente.
-- Esperado: [E-CLI-09] No existe un cliente con el NIT 8888888-8.
CALL sp_cliente_consultar('8888888-8');

-- Caso 3 (ERROR): NIT con formato inválido.
-- Esperado: [E-CLI-01] El NIT es inválido...
CALL sp_cliente_consultar('ABC');


-- =====================================================================
-- 8. sp_producto_consultar
-- =====================================================================

-- Caso 1 (ÉXITO): TSTP01. Esperado: unidades_vendidas = 3, monto_vendido = 75.00
-- (se vendió a 25.00 aunque su precio actual ahora sea 45.00).
CALL sp_producto_consultar('TSTP01');

-- Caso 2 (ÉXITO): TSTP02. Esperado: unidades_vendidas = 2, monto_vendido = 20.00
-- (la unidad de la factura anulada no cuenta).
CALL sp_producto_consultar('TSTP02');

-- Caso 3 (ERROR): producto inexistente.
-- Esperado: [E-PRO-07] No existe un producto con el código NOEXISTE9.
CALL sp_producto_consultar('NOEXISTE9');

-- Caso 4 (ERROR): código vacío.
-- Esperado: [E-PRO-01] El código del producto es obligatorio.
CALL sp_producto_consultar('   ');


-- =====================================================================
-- 7. sp_producto_eliminar (baja lógica) y efectos de la regla 10
-- =====================================================================

-- Caso 1 (ÉXITO): dar de baja el producto TSTP02.
-- Esperado: "Producto TSTP02 dado de baja (INACTIVO)."
CALL sp_producto_eliminar('TSTP02');

-- Caso 2 (ERROR): producto que ya está inactivo.
-- Esperado: [E-PRO-09] El producto ya estaba inactivo.
CALL sp_producto_eliminar('TSTP02');

-- Caso 3 (ERROR): producto inexistente.
-- Esperado: [E-PRO-07] No existe un producto con el código NOEXISTE9.
CALL sp_producto_eliminar('NOEXISTE9');

-- Efecto 1 (ERROR): vender un producto inactivo.
-- Esperado: [E-VTA-12] Alguno de los productos está inactivo y no puede venderse.
CALL sp_venta_registrar(@suc, 'TSTV01', '9900001-1', 'Efectivo', @det_inact);

-- Efecto 2 (ERROR): actualizar un producto inactivo.
-- Esperado: [E-PRO-08] El producto está inactivo y no puede modificarse.
CALL sp_producto_actualizar('TSTP02', 'Nuevo nombre', 15.00);


-- =====================================================================
-- 3. sp_cliente_eliminar (baja lógica) y efectos de la regla 10
-- =====================================================================

-- Caso 1 (ÉXITO): dar de baja al cliente 9900002-2.
-- Esperado: "Cliente con NIT 9900002-2 dado de baja (INACTIVO)."
CALL sp_cliente_eliminar('9900002-2');

-- Caso 2 (ERROR): cliente que ya está inactivo.
-- Esperado: [E-CLI-11] El cliente ya estaba inactivo.
CALL sp_cliente_eliminar('9900002-2');

-- Caso 3 (ERROR): cliente inexistente.
-- Esperado: [E-CLI-09] No existe un cliente con el NIT 8888888-8.
CALL sp_cliente_eliminar('8888888-8');

-- Efecto 1 (ERROR): facturar a un cliente inactivo.
-- Esperado: [E-VTA-07] El cliente está inactivo y no puede usarse en nuevas ventas.
CALL sp_venta_registrar(@suc, 'TSTV01', '9900002-2', 'Efectivo', @det_a);

-- Efecto 2 (ERROR): modificar un cliente inactivo.
-- Esperado: [E-CLI-10] El cliente está inactivo y no puede modificarse.
CALL sp_cliente_actualizar('9900002-2', '55558888', NULL, NULL, NULL);


-- =====================================================================
-- PRUEBA DE ATOMICIDAD (enunciado 6.6)
-- Se registra una venta cuya ÚLTIMA línea tiene un producto inexistente.
-- No debe quedar ni la factura ni ninguna de sus líneas.
-- =====================================================================
SET @facturas_antes = (SELECT COUNT(*) FROM factura);
SET @detalle_antes  = (SELECT COUNT(*) FROM detalle_factura);
SET @bitacora_antes = (SELECT COUNT(*) FROM bitacora);

-- Esperado: [E-VTA-11] Alguno de los productos indicados no existe.
CALL sp_venta_registrar(@suc, 'TSTV01', '9900001-1', 'Efectivo', @det_noex);

-- Verificación: los conteos de antes y después deben ser IGUALES.
SELECT @facturas_antes AS facturas_antes, (SELECT COUNT(*) FROM factura)         AS facturas_despues,
       @detalle_antes  AS detalle_antes,  (SELECT COUNT(*) FROM detalle_factura) AS detalle_despues,
       @bitacora_antes AS bitacora_antes, (SELECT COUNT(*) FROM bitacora)        AS bitacora_despues;

SELECT CASE
         WHEN @facturas_antes = (SELECT COUNT(*) FROM factura)
          AND @detalle_antes  = (SELECT COUNT(*) FROM detalle_factura)
          AND @bitacora_antes = (SELECT COUNT(*) FROM bitacora)
         THEN 'CORRECTO: no se creó la factura ni ninguna de sus líneas'
         ELSE 'FALLA: quedaron cambios a medias'
       END AS prueba_atomicidad;

-- El ROLLBACK de una falla a mitad de la transacción (después de haber
-- insertado la cabecera) se demuestra en 09_prueba_rollback.sql.


-- =====================================================================
-- TRIGGERS DE REGLAS DE NEGOCIO
-- Única excepción a "solo procedimientos": se intentan a propósito las
-- operaciones prohibidas para demostrar que los triggers las bloquean.
-- =====================================================================

-- Intento de ELIMINAR una factura (regla 9).
-- Esperado: [E-TRG-03] Las facturas no se eliminan: use sp_venta_anular.
DELETE FROM factura WHERE numero = @num_a;

-- Intento de ELIMINAR las líneas de una factura.
-- Esperado: [E-TRG-05] Las líneas de una factura no se eliminan: use sp_venta_anular.
DELETE FROM detalle_factura WHERE id_factura = @id_fac_a;

-- Intento de MODIFICAR una factura ANULADA (encabezado).
-- Esperado: [E-TRG-01] Una factura anulada no puede modificarse.
UPDATE factura SET total = 1 WHERE numero = @num_b;

-- Intento de MODIFICAR el detalle de una factura ANULADA.
-- Esperado: [E-TRG-04] Las líneas de una factura no se modifican...
UPDATE detalle_factura SET cantidad = 99 WHERE id_factura = @id_fac_b;

-- Verificación: nada se eliminó ni se alteró.
-- Esperado: factura_a = 1, lineas_a = 2, factura_b = "ANULADA / 10.00", lineas_b = 1.
SELECT (SELECT COUNT(*) FROM factura WHERE numero = @num_a)                AS factura_a,
       (SELECT COUNT(*) FROM detalle_factura WHERE id_factura = @id_fac_a) AS lineas_a,
       (SELECT CONCAT(estado, ' / ', total) FROM factura WHERE numero = @num_b) AS factura_b,
       (SELECT COUNT(*) FROM detalle_factura WHERE id_factura = @id_fac_b) AS lineas_b;


-- =====================================================================
-- BITÁCORA FINAL: registros generados por las pruebas
-- Esperado: 11 registros, uno por cada cambio EXITOSO sobre las tablas
-- auditadas (cliente, producto y factura):
--   cliente   INSERT x2   UPDATE x2 (actualización de 9900001-1 y baja de 9900002-2)
--   producto  INSERT x2 (TSTP01, TSTP02)
--             UPDATE x2 (precio de TSTP01 y baja de TSTP02)
--   factura   INSERT x2   UPDATE x1 (anulación de la segunda factura)
-- (vendedor y detalle_factura no se auditan: el enunciado pide clientes,
--  productos y facturas.)
-- Los casos con error no dejan registro: o se detuvieron antes de modificar
-- datos, o el ROLLBACK deshizo también lo que el trigger había escrito.
-- =====================================================================
SELECT tabla, operacion, COUNT(*) AS registros
FROM bitacora
WHERE id_bitacora > @bit_inicio
GROUP BY tabla, operacion
ORDER BY tabla, operacion;

SELECT COUNT(*) AS total_registros_de_las_pruebas   -- esperado: 11
FROM bitacora
WHERE id_bitacora > @bit_inicio;

SELECT id_bitacora, fecha_hora, usuario, tabla, operacion, id_registro,
       descripcion, datos_anteriores, datos_nuevos
FROM bitacora
WHERE id_bitacora > @bit_inicio
ORDER BY id_bitacora;