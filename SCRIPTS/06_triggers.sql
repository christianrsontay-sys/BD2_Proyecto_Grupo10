-- ##### ARCHIVO: 06_triggers.sql #####
/* =====================================================================
   06_triggers.sql
   Triggers requeridos por el enunciado (sección 6.5): 13 en total.

   A) AUDITORÍA (9): AFTER INSERT / UPDATE / DELETE sobre cliente, producto
      y factura (encabezado). Cada uno inserta en la tabla bitacora con la
      descripción construida por fn_descripcion_bitacora.

   B) REGLAS DE NEGOCIO (4):
        - no se eliminan facturas ni sus líneas (usar sp_venta_anular)
        - no se modifica una factura anulada ni su detalle

   Se crean DESPUÉS del ETL para que la carga inicial no llene la bitácora.
   Códigos de error: E-TRG-01 a E-TRG-05.
   Nota: las reglas de "cliente, vendedor o producto inactivo no se usa en
   ventas" (regla 10) las valida sp_venta_registrar.
   ===================================================================== */
USE Proyecto_SistemasVentasGranilocas_V2;

DROP TRIGGER IF EXISTS trg_cliente_ai;
DROP TRIGGER IF EXISTS trg_cliente_au;
DROP TRIGGER IF EXISTS trg_cliente_ad;
DROP TRIGGER IF EXISTS trg_producto_ai;
DROP TRIGGER IF EXISTS trg_producto_au;
DROP TRIGGER IF EXISTS trg_producto_ad;
DROP TRIGGER IF EXISTS trg_factura_ai;
DROP TRIGGER IF EXISTS trg_factura_au;
DROP TRIGGER IF EXISTS trg_factura_ad;
DROP TRIGGER IF EXISTS trg_factura_bu;
DROP TRIGGER IF EXISTS trg_factura_bd;
DROP TRIGGER IF EXISTS trg_detalle_bu;
DROP TRIGGER IF EXISTS trg_detalle_bd;
DELIMITER //

/* =====================================================================
   AUDITORÍA: CLIENTE
   ===================================================================== */
CREATE TRIGGER trg_cliente_ai
AFTER INSERT ON cliente
FOR EACH ROW
BEGIN
    INSERT INTO bitacora
        (usuario, tabla, operacion, id_registro, descripcion, datos_anteriores, datos_nuevos)
    VALUES
        (USER(), 'cliente', 'INSERT', NEW.id_cliente,
         fn_descripcion_bitacora('cliente', 'INSERT', CONCAT('cliente con NIT ', NEW.nit)),
         NULL,
         JSON_OBJECT('id_cliente', NEW.id_cliente, 'nit', NEW.nit, 'nombres', NEW.nombres,
                     'apellidos', NEW.apellidos, 'genero', NEW.genero,
                     'fecha_nacimiento', NEW.fecha_nacimiento, 'correo', NEW.correo,
                     'telefono', NEW.telefono, 'direccion', NEW.direccion,
                     'id_municipio', NEW.id_municipio, 'estado', NEW.estado));
END //
CREATE TRIGGER trg_cliente_au
AFTER UPDATE ON cliente
FOR EACH ROW
BEGIN
    DECLARE v_detalle VARCHAR(200);

    IF OLD.estado = 'ACTIVO' AND NEW.estado = 'INACTIVO' THEN
        SET v_detalle = CONCAT('baja lógica del cliente con NIT ', NEW.nit);
    ELSE
        SET v_detalle = CONCAT('cliente con NIT ', NEW.nit);
    END IF;

    INSERT INTO bitacora
        (usuario, tabla, operacion, id_registro, descripcion, datos_anteriores, datos_nuevos)
    VALUES
        (USER(), 'cliente', 'UPDATE', NEW.id_cliente,
         fn_descripcion_bitacora('cliente', 'UPDATE', v_detalle),
         JSON_OBJECT('id_cliente', OLD.id_cliente, 'nit', OLD.nit, 'nombres', OLD.nombres,
                     'apellidos', OLD.apellidos, 'genero', OLD.genero,
                     'fecha_nacimiento', OLD.fecha_nacimiento, 'correo', OLD.correo,
                     'telefono', OLD.telefono, 'direccion', OLD.direccion,
                     'id_municipio', OLD.id_municipio, 'estado', OLD.estado),
         JSON_OBJECT('id_cliente', NEW.id_cliente, 'nit', NEW.nit, 'nombres', NEW.nombres,
                     'apellidos', NEW.apellidos, 'genero', NEW.genero,
                     'fecha_nacimiento', NEW.fecha_nacimiento, 'correo', NEW.correo,
                     'telefono', NEW.telefono, 'direccion', NEW.direccion,
                     'id_municipio', NEW.id_municipio, 'estado', NEW.estado));
END //
CREATE TRIGGER trg_cliente_ad
AFTER DELETE ON cliente
FOR EACH ROW
BEGIN
    INSERT INTO bitacora
        (usuario, tabla, operacion, id_registro, descripcion, datos_anteriores, datos_nuevos)
    VALUES
        (USER(), 'cliente', 'DELETE', OLD.id_cliente,
         fn_descripcion_bitacora('cliente', 'DELETE', CONCAT('cliente con NIT ', OLD.nit)),
         JSON_OBJECT('id_cliente', OLD.id_cliente, 'nit', OLD.nit, 'nombres', OLD.nombres,
                     'apellidos', OLD.apellidos, 'genero', OLD.genero,
                     'fecha_nacimiento', OLD.fecha_nacimiento, 'correo', OLD.correo,
                     'telefono', OLD.telefono, 'direccion', OLD.direccion,
                     'id_municipio', OLD.id_municipio, 'estado', OLD.estado),
         NULL);
END //

/* =====================================================================
   AUDITORÍA: PRODUCTO
   ===================================================================== */
CREATE TRIGGER trg_producto_ai
AFTER INSERT ON producto
FOR EACH ROW
BEGIN
    INSERT INTO bitacora
        (usuario, tabla, operacion, id_registro, descripcion, datos_anteriores, datos_nuevos)
    VALUES
        (USER(), 'producto', 'INSERT', NEW.id_producto,
         fn_descripcion_bitacora('producto', 'INSERT', CONCAT('producto ', NEW.codigo)),
         NULL,
         JSON_OBJECT('id_producto', NEW.id_producto, 'codigo', NEW.codigo, 'nombre', NEW.nombre,
                     'id_categoria', NEW.id_categoria, 'id_marca', NEW.id_marca,
                     'precio_actual', NEW.precio_actual, 'estado', NEW.estado));
END //
CREATE TRIGGER trg_producto_au
AFTER UPDATE ON producto
FOR EACH ROW
BEGIN
    DECLARE v_detalle VARCHAR(200);

    IF OLD.estado = 'ACTIVO' AND NEW.estado = 'INACTIVO' THEN
        SET v_detalle = CONCAT('baja lógica del producto ', NEW.codigo);
    ELSEIF OLD.precio_actual <> NEW.precio_actual THEN
        SET v_detalle = CONCAT('producto ', NEW.codigo, ', precio de ', OLD.precio_actual, ' a ', NEW.precio_actual);
    ELSE
        SET v_detalle = CONCAT('producto ', NEW.codigo);
    END IF;

    INSERT INTO bitacora
        (usuario, tabla, operacion, id_registro, descripcion, datos_anteriores, datos_nuevos)
    VALUES
        (USER(), 'producto', 'UPDATE', NEW.id_producto,
         fn_descripcion_bitacora('producto', 'UPDATE', v_detalle),
         JSON_OBJECT('id_producto', OLD.id_producto, 'codigo', OLD.codigo, 'nombre', OLD.nombre,
                     'id_categoria', OLD.id_categoria, 'id_marca', OLD.id_marca,
                     'precio_actual', OLD.precio_actual, 'estado', OLD.estado),
         JSON_OBJECT('id_producto', NEW.id_producto, 'codigo', NEW.codigo, 'nombre', NEW.nombre,
                     'id_categoria', NEW.id_categoria, 'id_marca', NEW.id_marca,
                     'precio_actual', NEW.precio_actual, 'estado', NEW.estado));
END //
CREATE TRIGGER trg_producto_ad
AFTER DELETE ON producto
FOR EACH ROW
BEGIN
    INSERT INTO bitacora
        (usuario, tabla, operacion, id_registro, descripcion, datos_anteriores, datos_nuevos)
    VALUES
        (USER(), 'producto', 'DELETE', OLD.id_producto,
         fn_descripcion_bitacora('producto', 'DELETE', CONCAT('producto ', OLD.codigo)),
         JSON_OBJECT('id_producto', OLD.id_producto, 'codigo', OLD.codigo, 'nombre', OLD.nombre,
                     'id_categoria', OLD.id_categoria, 'id_marca', OLD.id_marca,
                     'precio_actual', OLD.precio_actual, 'estado', OLD.estado),
         NULL);
END //

/* =====================================================================
   AUDITORÍA: FACTURA (encabezado)
   ===================================================================== */
CREATE TRIGGER trg_factura_ai
AFTER INSERT ON factura
FOR EACH ROW
BEGIN
    INSERT INTO bitacora
        (usuario, tabla, operacion, id_registro, descripcion, datos_anteriores, datos_nuevos)
    VALUES
        (USER(), 'factura', 'INSERT', NEW.id_factura,
         fn_descripcion_bitacora('factura', 'INSERT', CONCAT('factura ', NEW.numero, ', total ', NEW.total)),
         NULL,
         JSON_OBJECT('id_factura', NEW.id_factura, 'numero', NEW.numero, 'fecha', NEW.fecha,
                     'hora', NEW.hora, 'id_sucursal', NEW.id_sucursal, 'id_vendedor', NEW.id_vendedor,
                     'id_cliente', NEW.id_cliente, 'id_metodo_pago', NEW.id_metodo_pago,
                     'total', NEW.total, 'estado', NEW.estado,
                     'fecha_anulacion', NEW.fecha_anulacion, 'motivo_anulacion', NEW.motivo_anulacion));
END //
CREATE TRIGGER trg_factura_au
AFTER UPDATE ON factura
FOR EACH ROW
BEGIN
    DECLARE v_descripcion VARCHAR(255);

    -- Ejemplo: "Se anuló la factura 107666. Motivo: error en el cliente"
    IF OLD.estado = 'EMITIDA' AND NEW.estado = 'ANULADA' THEN
        SET v_descripcion = fn_descripcion_bitacora('factura', 'ANULAR',
                                CONCAT(NEW.numero, '. Motivo: ', NEW.motivo_anulacion));
    ELSE
        SET v_descripcion = fn_descripcion_bitacora('factura', 'UPDATE', CONCAT('factura ', NEW.numero));
    END IF;

    INSERT INTO bitacora
        (usuario, tabla, operacion, id_registro, descripcion, datos_anteriores, datos_nuevos)
    VALUES
        (USER(), 'factura', 'UPDATE', NEW.id_factura, v_descripcion,
         JSON_OBJECT('id_factura', OLD.id_factura, 'numero', OLD.numero, 'total', OLD.total,
                     'estado', OLD.estado, 'fecha_anulacion', OLD.fecha_anulacion,
                     'motivo_anulacion', OLD.motivo_anulacion),
         JSON_OBJECT('id_factura', NEW.id_factura, 'numero', NEW.numero, 'total', NEW.total,
                     'estado', NEW.estado, 'fecha_anulacion', NEW.fecha_anulacion,
                     'motivo_anulacion', NEW.motivo_anulacion));
END //
-- Requerido por 6.5 (AFTER DELETE sobre facturas). Como el BEFORE DELETE bloquea
-- el borrado, este trigger queda como respaldo de auditoría.
CREATE TRIGGER trg_factura_ad
AFTER DELETE ON factura
FOR EACH ROW
BEGIN
    INSERT INTO bitacora
        (usuario, tabla, operacion, id_registro, descripcion, datos_anteriores, datos_nuevos)
    VALUES
        (USER(), 'factura', 'DELETE', OLD.id_factura,
         fn_descripcion_bitacora('factura', 'DELETE', CONCAT('factura ', OLD.numero)),
         JSON_OBJECT('id_factura', OLD.id_factura, 'numero', OLD.numero, 'total', OLD.total,
                     'estado', OLD.estado),
         NULL);
END //

/* =====================================================================
   REGLAS DE NEGOCIO
   ===================================================================== */
-- Regla de negocio: una factura anulada no se toca; en una emitida solo puede cambiar la anulación
CREATE TRIGGER trg_factura_bu
BEFORE UPDATE ON factura
FOR EACH ROW
BEGIN
    IF OLD.estado = 'ANULADA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-TRG-01] Una factura anulada no puede modificarse.';
    END IF;

    IF NOT (NEW.numero         <=> OLD.numero
        AND NEW.fecha          <=> OLD.fecha
        AND NEW.hora           <=> OLD.hora
        AND NEW.id_sucursal    <=> OLD.id_sucursal
        AND NEW.id_vendedor    <=> OLD.id_vendedor
        AND NEW.id_cliente     <=> OLD.id_cliente
        AND NEW.id_metodo_pago <=> OLD.id_metodo_pago
        AND NEW.total          <=> OLD.total) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-TRG-02] Una factura emitida solo puede cambiar su estado de anulación.';
    END IF;
END //
-- Regla de negocio (regla 9): las facturas nunca se eliminan físicamente
CREATE TRIGGER trg_factura_bd
BEFORE DELETE ON factura
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '[E-TRG-03] Las facturas no se eliminan: use sp_venta_anular.';
END //
-- Las líneas de una factura (anulada o vigente) no se modifican
CREATE TRIGGER trg_detalle_bu
BEFORE UPDATE ON detalle_factura
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '[E-TRG-04] Las líneas de una factura no se modifican; si hay un error, anule la factura con sp_venta_anular.';
END //
-- Las líneas de una factura nunca se eliminan físicamente
CREATE TRIGGER trg_detalle_bd
BEFORE DELETE ON detalle_factura
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '[E-TRG-05] Las líneas de una factura no se eliminan: use sp_venta_anular.';
END //

DELIMITER ;

SELECT COUNT(*) AS triggers FROM information_schema.triggers;
SELECT COUNT(*) AS filas_bitacora FROM Proyecto_SistemasVentasGranilocas_V2.bitacora;
WHERE trigger_schema = 'Proyecto_SistemasVentasGranilocas_V2';
