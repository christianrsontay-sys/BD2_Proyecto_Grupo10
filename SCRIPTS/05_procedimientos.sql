-- ##### ARCHIVO: 05_procedimientos.sql #####
/* =====================================================================
   05_procedimientos.sql
   Los 12 procedimientos mínimos del enunciado (sección 6.4).
   Esquema común: 1) limpiar parámetros  2) validar (SIGNAL con código)
                  3) START TRANSACTION   4) operación   5) COMMIT   6) mensaje
   El EXIT HANDLER hace ROLLBACK y relanza el error (RESIGNAL).

   Códigos de error:
     E-CLI-nn clientes   E-PRO-nn productos   E-VEN-nn vendedores
     E-VTA-nn ventas     (E-TRG-nn los lanzan los triggers, script 06)

     #  Procedimiento
     1  sp_cliente_crear          7  sp_producto_eliminar
     2  sp_cliente_actualizar     8  sp_producto_consultar
     3  sp_cliente_eliminar       9  sp_vendedor_crear
     4  sp_cliente_consultar     10  sp_venta_registrar
     5  sp_producto_crear        11  sp_venta_anular
     6  sp_producto_actualizar   12  sp_venta_consultar
   ===================================================================== */
USE Proyecto_SistemasVentasGranilocas_V2;

DROP PROCEDURE IF EXISTS sp_cliente_crear;
DROP PROCEDURE IF EXISTS sp_cliente_actualizar;
DROP PROCEDURE IF EXISTS sp_cliente_eliminar;
DROP PROCEDURE IF EXISTS sp_cliente_consultar;
DROP PROCEDURE IF EXISTS sp_producto_crear;
DROP PROCEDURE IF EXISTS sp_producto_actualizar;
DROP PROCEDURE IF EXISTS sp_producto_eliminar;
DROP PROCEDURE IF EXISTS sp_producto_consultar;
DROP PROCEDURE IF EXISTS sp_vendedor_crear;
DROP PROCEDURE IF EXISTS sp_venta_registrar;
DROP PROCEDURE IF EXISTS sp_venta_anular;
DROP PROCEDURE IF EXISTS sp_venta_consultar;
DELIMITER //

/* =====================================================================
   1. sp_cliente_crear
   Validaciones: NIT válido y no registrado; nombres y apellidos no vacíos;
   género M o F; fecha de nacimiento no futura; teléfono de 8 dígitos;
   correo válido y no registrado; el municipio existe.
   El municipio se envía por NOMBRE (o por su id si el nombre se repite
   en varios departamentos).
   Uso: CALL sp_cliente_crear('1234567-8','Ana','López','F','1990-05-20',
                              '55550001','ana@correo.com','Calle 1','Cobán');
   ===================================================================== */
CREATE PROCEDURE sp_cliente_crear(
    IN p_nit              VARCHAR(50),
    IN p_nombres          VARCHAR(60),
    IN p_apellidos        VARCHAR(60),
    IN p_genero           CHAR(1),
    IN p_fecha_nacimiento DATE,
    IN p_telefono         VARCHAR(20),
    IN p_correo           VARCHAR(255),
    IN p_direccion        VARCHAR(200),
    IN p_municipio        VARCHAR(60)
)
BEGIN
    DECLARE v_id_municipio INT DEFAULT NULL;
    DECLARE v_id_cliente   INT;
    DECLARE v_mensaje      VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- 1. Limpieza
    SET p_nit       = TRIM(p_nit);
    SET p_nombres   = TRIM(p_nombres);
    SET p_apellidos = TRIM(p_apellidos);
    SET p_genero    = UPPER(TRIM(p_genero));
    SET p_telefono  = TRIM(p_telefono);
    SET p_correo    = TRIM(p_correo);

    -- 2. Validaciones de formato (en el orden del enunciado)
    IF fn_validar_nit(p_nit) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-01] El NIT es inválido: solo dígitos, o dígitos-guion-dígito (ej. 1234567-8).';
    END IF;

    IF fn_nombre_valido(p_nombres) = 0 OR fn_nombre_valido(p_apellidos) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-02] Los nombres o apellidos están vacíos o tienen caracteres no permitidos.';
    END IF;

    IF p_genero IS NULL OR p_genero NOT IN ('M', 'F') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-03] El género debe ser M o F.';
    END IF;

    IF p_fecha_nacimiento IS NULL OR p_fecha_nacimiento > CURDATE() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-04] La fecha de nacimiento es obligatoria y no puede ser futura.';
    END IF;

    IF p_telefono IS NULL OR p_telefono NOT REGEXP '^[0-9]{8}$' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-12] El teléfono debe tener exactamente 8 dígitos.';
    END IF;

    IF fn_validar_correo(p_correo) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-05] El correo electrónico tiene un formato inválido.';
    END IF;

    -- Unicidad (regla 4)
    IF EXISTS (SELECT 1 FROM cliente WHERE nit = p_nit) THEN
        SET v_mensaje = CONCAT('[E-CLI-06] Ya existe un cliente con el NIT ', p_nit, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF EXISTS (SELECT 1 FROM cliente WHERE correo = p_correo) THEN
        SET v_mensaje = CONCAT('[E-CLI-07] Ya existe un cliente con el correo ', p_correo, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    -- Municipio
    SET v_id_municipio = fn_id_municipio(p_municipio);
    IF v_id_municipio IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-08] El municipio indicado no existe.';
    END IF;
    IF v_id_municipio = -1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-13] Hay varios municipios con ese nombre; envíe el id_municipio.';
    END IF;

    -- 3-5. Operación con transacción
    START TRANSACTION;
    INSERT INTO cliente
        (nit, nombres, apellidos, genero, fecha_nacimiento, correo, telefono, direccion, id_municipio)
    VALUES
        (p_nit, p_nombres, p_apellidos, p_genero, p_fecha_nacimiento, p_correo, p_telefono, p_direccion, v_id_municipio);
    SET v_id_cliente = LAST_INSERT_ID();
    COMMIT;

    -- 6. Confirmación
    SELECT CONCAT('Cliente con NIT ', p_nit, ' registrado correctamente.') AS mensaje,
           v_id_cliente AS id_cliente;
END //

/* =====================================================================
   2. sp_cliente_actualizar
   Cambia teléfono, correo, dirección y/o municipio. Un parámetro en NULL
   significa "dejar el valor actual".
   Validaciones: el cliente existe y está activo; mismas validaciones de
   formato; el correo no pertenece a otro cliente.
   ===================================================================== */
CREATE PROCEDURE sp_cliente_actualizar(
    IN p_nit       VARCHAR(50),
    IN p_telefono  VARCHAR(20),
    IN p_correo    VARCHAR(255),
    IN p_direccion VARCHAR(200),
    IN p_municipio VARCHAR(60)
)
BEGIN
    DECLARE v_id_cliente   INT DEFAULT NULL;
    DECLARE v_estado       VARCHAR(10);
    DECLARE v_id_municipio INT DEFAULT NULL;
    DECLARE v_mensaje      VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_nit      = TRIM(p_nit);
    SET p_telefono = TRIM(p_telefono);
    SET p_correo   = TRIM(p_correo);

    IF fn_validar_nit(p_nit) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-01] El NIT es inválido: solo dígitos, o dígitos-guion-dígito (ej. 1234567-8).';
    END IF;

    SELECT id_cliente, estado, id_municipio INTO v_id_cliente, v_estado, v_id_municipio
    FROM cliente WHERE nit = p_nit;

    IF v_id_cliente IS NULL THEN
        SET v_mensaje = CONCAT('[E-CLI-09] No existe un cliente con el NIT ', p_nit, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF v_estado <> 'ACTIVO' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-10] El cliente está inactivo y no puede modificarse.';
    END IF;

    IF p_telefono IS NOT NULL AND p_telefono NOT REGEXP '^[0-9]{8}$' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-12] El teléfono debe tener exactamente 8 dígitos.';
    END IF;

    IF p_correo IS NOT NULL THEN
        IF fn_validar_correo(p_correo) = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = '[E-CLI-05] El correo electrónico tiene un formato inválido.';
        END IF;
        IF EXISTS (SELECT 1 FROM cliente WHERE correo = p_correo AND id_cliente <> v_id_cliente) THEN
            SET v_mensaje = CONCAT('[E-CLI-07] Ya existe otro cliente con el correo ', p_correo, '.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
        END IF;
    END IF;

    IF p_municipio IS NOT NULL THEN
        SET v_id_municipio = fn_id_municipio(p_municipio);
        IF v_id_municipio IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = '[E-CLI-08] El municipio indicado no existe.';
        END IF;
        IF v_id_municipio = -1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = '[E-CLI-13] Hay varios municipios con ese nombre; envíe el id_municipio.';
        END IF;
    END IF;

    START TRANSACTION;
    UPDATE cliente
    SET telefono     = COALESCE(p_telefono,  telefono),
        correo       = COALESCE(p_correo,    correo),
        direccion    = COALESCE(p_direccion, direccion),
        id_municipio = v_id_municipio
    WHERE id_cliente = v_id_cliente;
    COMMIT;

    SELECT CONCAT('Cliente con NIT ', p_nit, ' actualizado correctamente.') AS mensaje;
END //

/* =====================================================================
   3. sp_cliente_eliminar
   Baja LÓGICA (estado INACTIVO). Nunca borra la fila (regla 10).
   Validaciones: el cliente existe y está activo.
   ===================================================================== */
CREATE PROCEDURE sp_cliente_eliminar(IN p_nit VARCHAR(50))
BEGIN
    DECLARE v_id_cliente INT DEFAULT NULL;
    DECLARE v_estado     VARCHAR(10);
    DECLARE v_mensaje    VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_nit = TRIM(p_nit);

    IF fn_validar_nit(p_nit) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-01] El NIT es inválido: solo dígitos, o dígitos-guion-dígito (ej. 1234567-8).';
    END IF;

    SELECT id_cliente, estado INTO v_id_cliente, v_estado
    FROM cliente WHERE nit = p_nit;

    IF v_id_cliente IS NULL THEN
        SET v_mensaje = CONCAT('[E-CLI-09] No existe un cliente con el NIT ', p_nit, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF v_estado = 'INACTIVO' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-11] El cliente ya estaba inactivo.';
    END IF;

    START TRANSACTION;
    UPDATE cliente SET estado = 'INACTIVO' WHERE id_cliente = v_id_cliente;
    COMMIT;

    SELECT CONCAT('Cliente con NIT ', p_nit, ' dado de baja (INACTIVO).') AS mensaje;
END //

/* =====================================================================
   4. sp_cliente_consultar
   Retorna sus datos, nombre completo, municipio, departamento, cantidad de
   compras vigentes (facturas no anuladas) y monto total comprado.
   ===================================================================== */
CREATE PROCEDURE sp_cliente_consultar(IN p_nit VARCHAR(50))
BEGIN
    DECLARE v_id_cliente INT DEFAULT NULL;
    DECLARE v_mensaje    VARCHAR(255);

    SET p_nit = TRIM(p_nit);

    IF fn_validar_nit(p_nit) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-CLI-01] El NIT es inválido: solo dígitos, o dígitos-guion-dígito (ej. 1234567-8).';
    END IF;

    SELECT id_cliente INTO v_id_cliente FROM cliente WHERE nit = p_nit;

    IF v_id_cliente IS NULL THEN
        SET v_mensaje = CONCAT('[E-CLI-09] No existe un cliente con el NIT ', p_nit, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    SELECT c.nit,
           CONCAT(c.nombres, ' ', c.apellidos) AS nombre_completo,
           c.genero, c.fecha_nacimiento, c.telefono, c.correo, c.direccion,
           m.nombre AS municipio,
           d.nombre AS departamento,
           c.estado,
           (SELECT COUNT(*) FROM factura f
            WHERE f.id_cliente = c.id_cliente AND f.estado = 'EMITIDA')                  AS compras_vigentes,
           (SELECT COALESCE(SUM(f.total), 0) FROM factura f
            WHERE f.id_cliente = c.id_cliente AND f.estado = 'EMITIDA')                  AS monto_total_comprado
    FROM cliente c
    JOIN municipio m    ON m.id_municipio = c.id_municipio
    JOIN departamento d ON d.id_departamento = m.id_departamento
    WHERE c.id_cliente = v_id_cliente;
END //

/* =====================================================================
   5. sp_producto_crear
   Validaciones: código no registrado; nombre no vacío; la categoría y la
   marca existen; precio mayor que cero.
   ===================================================================== */
CREATE PROCEDURE sp_producto_crear(
    IN p_codigo    VARCHAR(20),
    IN p_nombre    VARCHAR(200),
    IN p_categoria VARCHAR(60),
    IN p_marca     VARCHAR(60),
    IN p_precio    DECIMAL(12,2)
)
BEGIN
    DECLARE v_id_categoria INT DEFAULT NULL;
    DECLARE v_id_marca     INT DEFAULT NULL;
    DECLARE v_id_producto  INT;
    DECLARE v_mensaje      VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_codigo    = UPPER(TRIM(p_codigo));
    SET p_nombre    = TRIM(p_nombre);
    SET p_categoria = TRIM(p_categoria);
    SET p_marca     = TRIM(p_marca);

    IF p_codigo IS NULL OR p_codigo NOT REGEXP '^[A-Z0-9-]{3,10}$' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-PRO-01] El código es obligatorio: de 3 a 10 letras, números o guiones.';
    END IF;

    IF fn_texto_valido(p_nombre, 120) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-PRO-02] El nombre del producto está vacío o tiene caracteres no permitidos.';
    END IF;

    IF p_precio IS NULL OR p_precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-PRO-03] El precio debe ser mayor que cero.';
    END IF;

    IF EXISTS (SELECT 1 FROM producto WHERE codigo = p_codigo) THEN
        SET v_mensaje = CONCAT('[E-PRO-04] Ya existe un producto con el código ', p_codigo, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    SELECT id_categoria INTO v_id_categoria FROM categoria WHERE nombre = p_categoria;
    IF v_id_categoria IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-PRO-05] La categoría indicada no existe.';
    END IF;

    SELECT id_marca INTO v_id_marca FROM marca WHERE nombre = p_marca;
    IF v_id_marca IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-PRO-06] La marca indicada no existe.';
    END IF;

    START TRANSACTION;
    INSERT INTO producto (codigo, nombre, id_categoria, id_marca, precio_actual)
    VALUES (p_codigo, p_nombre, v_id_categoria, v_id_marca, p_precio);
    SET v_id_producto = LAST_INSERT_ID();
    COMMIT;

    SELECT CONCAT('Producto ', p_codigo, ' registrado correctamente.') AS mensaje,
           v_id_producto AS id_producto;
END //

/* =====================================================================
   6. sp_producto_actualizar
   Cambia nombre y/o precio (NULL = dejar el valor actual).
   Validaciones: el producto existe y está activo; precio mayor que cero.
   Las ventas históricas NO se alteran: cada línea de factura conserva su
   propio precio_unitario (regla 6).
   ===================================================================== */
CREATE PROCEDURE sp_producto_actualizar(
    IN p_codigo VARCHAR(20),
    IN p_nombre VARCHAR(200),
    IN p_precio DECIMAL(12,2)
)
BEGIN
    DECLARE v_id_producto INT DEFAULT NULL;
    DECLARE v_estado      VARCHAR(10);
    DECLARE v_precio_ant  DECIMAL(12,2);
    DECLARE v_mensaje     VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_codigo = UPPER(TRIM(p_codigo));
    SET p_nombre = TRIM(p_nombre);

    SELECT id_producto, estado, precio_actual INTO v_id_producto, v_estado, v_precio_ant
    FROM producto WHERE codigo = p_codigo;

    IF v_id_producto IS NULL THEN
        SET v_mensaje = CONCAT('[E-PRO-07] No existe un producto con el código ', COALESCE(p_codigo, 'NULL'), '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF v_estado <> 'ACTIVO' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-PRO-08] El producto está inactivo y no puede modificarse.';
    END IF;

    IF p_nombre IS NOT NULL AND fn_texto_valido(p_nombre, 120) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-PRO-02] El nombre del producto está vacío o tiene caracteres no permitidos.';
    END IF;

    IF p_precio IS NOT NULL AND p_precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-PRO-03] El precio debe ser mayor que cero.';
    END IF;

    START TRANSACTION;
    UPDATE producto
    SET nombre        = COALESCE(p_nombre, nombre),
        precio_actual = COALESCE(p_precio, precio_actual)
    WHERE id_producto = v_id_producto;
    COMMIT;

    SELECT CONCAT('Producto ', p_codigo, ' actualizado correctamente.') AS mensaje,
           v_precio_ant AS precio_anterior,
           COALESCE(p_precio, v_precio_ant) AS precio_nuevo;
END //

/* =====================================================================
   7. sp_producto_eliminar
   Baja LÓGICA (estado INACTIVO). Validaciones: existe y está activo.
   ===================================================================== */
CREATE PROCEDURE sp_producto_eliminar(IN p_codigo VARCHAR(20))
BEGIN
    DECLARE v_id_producto INT DEFAULT NULL;
    DECLARE v_estado      VARCHAR(10);
    DECLARE v_mensaje     VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_codigo = UPPER(TRIM(p_codigo));

    SELECT id_producto, estado INTO v_id_producto, v_estado
    FROM producto WHERE codigo = p_codigo;

    IF v_id_producto IS NULL THEN
        SET v_mensaje = CONCAT('[E-PRO-07] No existe un producto con el código ', COALESCE(p_codigo, 'NULL'), '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF v_estado = 'INACTIVO' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-PRO-09] El producto ya estaba inactivo.';
    END IF;

    START TRANSACTION;
    UPDATE producto SET estado = 'INACTIVO' WHERE id_producto = v_id_producto;
    COMMIT;

    SELECT CONCAT('Producto ', p_codigo, ' dado de baja (INACTIVO).') AS mensaje;
END //

/* =====================================================================
   8. sp_producto_consultar
   Retorna sus datos, categoría, marca, unidades vendidas y monto vendido
   (solo facturas vigentes, es decir, no anuladas).
   ===================================================================== */
CREATE PROCEDURE sp_producto_consultar(IN p_codigo VARCHAR(20))
BEGIN
    DECLARE v_id_producto INT DEFAULT NULL;
    DECLARE v_mensaje     VARCHAR(255);

    SET p_codigo = UPPER(TRIM(p_codigo));

    IF p_codigo IS NULL OR p_codigo = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-PRO-01] El código del producto es obligatorio.';
    END IF;

    SELECT id_producto INTO v_id_producto FROM producto WHERE codigo = p_codigo;

    IF v_id_producto IS NULL THEN
        SET v_mensaje = CONCAT('[E-PRO-07] No existe un producto con el código ', p_codigo, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    SELECT p.codigo, p.nombre,
           c.nombre AS categoria,
           m.nombre AS marca,
           p.precio_actual, p.estado,
           COALESCE((SELECT SUM(d.cantidad)
                     FROM detalle_factura d
                     JOIN factura f ON f.id_factura = d.id_factura
                     WHERE d.id_producto = p.id_producto AND f.estado = 'EMITIDA'), 0) AS unidades_vendidas,
           COALESCE((SELECT SUM(d.subtotal)
                     FROM detalle_factura d
                     JOIN factura f ON f.id_factura = d.id_factura
                     WHERE d.id_producto = p.id_producto AND f.estado = 'EMITIDA'), 0) AS monto_vendido
    FROM producto p
    JOIN categoria c ON c.id_categoria = p.id_categoria
    JOIN marca m     ON m.id_marca = p.id_marca
    WHERE p.id_producto = v_id_producto;
END //

/* =====================================================================
   9. sp_vendedor_crear
   Validaciones: código no registrado; nombres y apellidos no vacíos; la
   sucursal existe. El vendedor queda asignado a UNA sola sucursal (regla 3).
   ===================================================================== */
CREATE PROCEDURE sp_vendedor_crear(
    IN p_codigo          VARCHAR(20),
    IN p_nombres         VARCHAR(60),
    IN p_apellidos       VARCHAR(60),
    IN p_codigo_sucursal VARCHAR(20)
)
BEGIN
    DECLARE v_id_sucursal INT DEFAULT NULL;
    DECLARE v_id_vendedor INT;
    DECLARE v_mensaje     VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_codigo          = UPPER(TRIM(p_codigo));
    SET p_nombres         = TRIM(p_nombres);
    SET p_apellidos       = TRIM(p_apellidos);
    SET p_codigo_sucursal = TRIM(p_codigo_sucursal);

    IF p_codigo IS NULL OR p_codigo NOT REGEXP '^[A-Z0-9-]{3,10}$' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VEN-01] El código es obligatorio: de 3 a 10 letras, números o guiones.';
    END IF;

    IF fn_nombre_valido(p_nombres) = 0 OR fn_nombre_valido(p_apellidos) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VEN-02] Los nombres o apellidos están vacíos o tienen caracteres no permitidos.';
    END IF;

    IF EXISTS (SELECT 1 FROM vendedor WHERE codigo = p_codigo) THEN
        SET v_mensaje = CONCAT('[E-VEN-03] Ya existe un vendedor con el código ', p_codigo, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    SELECT id_sucursal INTO v_id_sucursal FROM sucursal WHERE codigo = p_codigo_sucursal;
    IF v_id_sucursal IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VEN-04] La sucursal indicada no existe.';
    END IF;

    START TRANSACTION;
    INSERT INTO vendedor (codigo, nombres, apellidos, id_sucursal)
    VALUES (p_codigo, p_nombres, p_apellidos, v_id_sucursal);
    SET v_id_vendedor = LAST_INSERT_ID();
    COMMIT;

    SELECT CONCAT('Vendedor ', p_codigo, ' registrado correctamente.') AS mensaje,
           v_id_vendedor AS id_vendedor;
END //

/* =====================================================================
   10. sp_venta_registrar  (TRANSACCIONAL)
   Parámetros: sucursal, vendedor, nit del cliente, método de pago, detalle (JSON).
   Crea la factura COMPLETA (cabecera + líneas) en una sola transacción:
   o se guarda todo o no se guarda nada.

   Detalle (Anexo A del enunciado): arreglo JSON, una entrada por línea:
      '[{"codigo_producto":"PRD0001","cantidad":3},{"codigo_producto":"PRD0045","cantidad":1}]'
   (por tolerancia también se aceptan las claves "codigo" o "producto").
   El precio de cada línea se toma de producto.precio_actual y se COPIA al
   detalle (regla 6). Fecha y hora son las del servidor.

   El número de factura es el correlativo siguiente al mayor existente; un
   bloqueo (GET_LOCK) impide que dos ventas simultáneas obtengan el mismo.

   RETORNO: el resultado trae numero_factura y total (calculado con
   fn_total_factura). Además deja ambos valores en las variables de sesión
   @numero_factura_generado y @total_factura_generado, para que un script
   pueda usar el número devuelto:
        CALL sp_venta_registrar(...);
        SET @num = @numero_factura_generado;
   ===================================================================== */
CREATE PROCEDURE sp_venta_registrar(
    IN p_codigo_sucursal VARCHAR(20),
    IN p_codigo_vendedor VARCHAR(20),
    IN p_nit_cliente     VARCHAR(50),
    IN p_metodo_pago     VARCHAR(30),
    IN p_detalle         TEXT
)
BEGIN
    DECLARE v_id_vendedor       INT DEFAULT NULL;
    DECLARE v_sucursal_vendedor INT;
    DECLARE v_estado_vendedor   VARCHAR(10);
    DECLARE v_id_sucursal       INT DEFAULT NULL;
    DECLARE v_id_cliente        INT DEFAULT NULL;
    DECLARE v_estado_cliente    VARCHAR(10);
    DECLARE v_id_metodo         INT DEFAULT NULL;
    DECLARE v_numero            VARCHAR(20);
    DECLARE v_id_factura        INT;
    DECLARE v_total             DECIMAL(12,2);
    DECLARE v_mensaje           VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DO RELEASE_LOCK('sp_venta_registrar_numero');
        DROP TEMPORARY TABLE IF EXISTS tmp_venta_lineas;
        RESIGNAL;
    END;

    SET p_codigo_sucursal = TRIM(p_codigo_sucursal);
    SET p_codigo_vendedor = TRIM(p_codigo_vendedor);
    SET p_nit_cliente     = TRIM(p_nit_cliente);
    SET p_metodo_pago     = TRIM(p_metodo_pago);

    -- Validar el JSON del detalle
    IF p_detalle IS NULL OR JSON_VALID(p_detalle) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-01] El detalle debe enviarse como un arreglo JSON válido con al menos una línea.';
    END IF;
    IF JSON_TYPE(p_detalle) <> 'ARRAY' OR JSON_LENGTH(p_detalle) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-01] El detalle debe enviarse como un arreglo JSON válido con al menos una línea.';
    END IF;

    -- Vendedor (regla 1 y 3)
    SELECT id_vendedor, id_sucursal, estado
      INTO v_id_vendedor, v_sucursal_vendedor, v_estado_vendedor
    FROM vendedor WHERE codigo = UPPER(p_codigo_vendedor);

    IF v_id_vendedor IS NULL THEN
        SET v_mensaje = CONCAT('[E-VTA-02] No existe el vendedor ', COALESCE(p_codigo_vendedor, 'NULL'), '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF v_estado_vendedor <> 'ACTIVO' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-03] El vendedor está inactivo.';
    END IF;

    -- Sucursal
    SELECT id_sucursal INTO v_id_sucursal FROM sucursal WHERE codigo = UPPER(p_codigo_sucursal);
    IF v_id_sucursal IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-04] La sucursal indicada no existe.';
    END IF;

    IF v_sucursal_vendedor <> v_id_sucursal THEN
        SET v_mensaje = CONCAT('[E-VTA-05] El vendedor ', p_codigo_vendedor,
                               ' no pertenece a la sucursal ', p_codigo_sucursal, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    -- Cliente (regla 10: debe estar activo)
    SELECT id_cliente, estado INTO v_id_cliente, v_estado_cliente
    FROM cliente WHERE nit = p_nit_cliente;

    IF v_id_cliente IS NULL THEN
        SET v_mensaje = CONCAT('[E-VTA-06] No existe un cliente con el NIT ', COALESCE(p_nit_cliente, 'NULL'), '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF v_estado_cliente <> 'ACTIVO' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-07] El cliente está inactivo y no puede usarse en nuevas ventas.';
    END IF;

    -- Método de pago
    SELECT id_metodo_pago INTO v_id_metodo FROM metodo_pago WHERE nombre = p_metodo_pago;
    IF v_id_metodo IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-08] El método de pago debe ser Efectivo, Tarjeta o Transferencia.';
    END IF;

    -- Las líneas del JSON se pasan a una tabla temporal (solo existe en esta sesión)
    DROP TEMPORARY TABLE IF EXISTS tmp_venta_lineas;
    CREATE TEMPORARY TABLE tmp_venta_lineas (
        codigo   VARCHAR(10) NULL,
        cantidad INT         NULL
    );

    INSERT INTO tmp_venta_lineas (codigo, cantidad)
    SELECT UPPER(TRIM(COALESCE(l.c1, l.c2, l.c3))), l.cant
    FROM JSON_TABLE(p_detalle, '$[*]' COLUMNS (
            c1   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$.codigo_producto',
            c2   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$.codigo',
            c3   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci PATH '$.producto',
            cant INT PATH '$.cantidad')) AS l;

    -- Cada línea necesita código y cantidad entera positiva
    IF EXISTS (SELECT 1 FROM tmp_venta_lineas
               WHERE codigo IS NULL OR codigo = '' OR cantidad IS NULL OR cantidad <= 0) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-09] Cada línea necesita un código y una cantidad entera mayor que cero.';
    END IF;

    -- Regla 2: un producto aparece en una sola línea
    IF EXISTS (SELECT 1 FROM tmp_venta_lineas GROUP BY codigo HAVING COUNT(*) > 1) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-10] Un producto no puede repetirse en la misma factura.';
    END IF;

    -- Productos inexistentes (cualquier línea, incluida la última)
    IF EXISTS (SELECT 1 FROM tmp_venta_lineas l
               LEFT JOIN producto p ON p.codigo = l.codigo
               WHERE p.id_producto IS NULL) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-11] Alguno de los productos indicados no existe.';
    END IF;

    -- Productos inactivos (regla 10)
    IF EXISTS (SELECT 1 FROM tmp_venta_lineas l
               JOIN producto p ON p.codigo = l.codigo
               WHERE p.estado <> 'ACTIVO') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-12] Alguno de los productos está inactivo y no puede venderse.';
    END IF;

    -- Total esperado (regla 8)
    SELECT SUM(p.precio_actual * l.cantidad) INTO v_total
    FROM tmp_venta_lineas l
    JOIN producto p ON p.codigo = l.codigo;

    -- Bloqueo para que el correlativo no se duplique entre ventas simultáneas
    IF GET_LOCK('sp_venta_registrar_numero', 10) <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-18] No se pudo obtener el correlativo de factura; intente de nuevo.';
    END IF;

    -- Operación atómica
    START TRANSACTION;

    SELECT CAST(COALESCE(MAX(CAST(numero AS UNSIGNED)), 100000) + 1 AS CHAR)
      INTO v_numero FROM factura;

    INSERT INTO factura
        (numero, fecha, hora, id_sucursal, id_vendedor, id_cliente, id_metodo_pago, total, estado)
    VALUES
        (v_numero, CURDATE(), CURTIME(), v_id_sucursal, v_id_vendedor, v_id_cliente, v_id_metodo, v_total, 'EMITIDA');

    SELECT id_factura INTO v_id_factura FROM factura WHERE numero = v_numero;

    INSERT INTO detalle_factura (id_factura, id_producto, cantidad, precio_unitario, subtotal)
    SELECT v_id_factura, p.id_producto, l.cantidad, p.precio_actual, p.precio_actual * l.cantidad
    FROM tmp_venta_lineas l
    JOIN producto p ON p.codigo = l.codigo;

    -- Verificación final con la función: el total guardado debe ser la suma del detalle
    IF fn_total_factura(v_id_factura) <> v_total THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-13] El total de la factura no coincide con la suma de su detalle.';
    END IF;

    COMMIT;

    DO RELEASE_LOCK('sp_venta_registrar_numero');
    DROP TEMPORARY TABLE IF EXISTS tmp_venta_lineas;

    -- Retorno: número de factura y total calculado con fn_total_factura
    SET @numero_factura_generado = v_numero;
    SET @total_factura_generado  = fn_total_factura(v_id_factura);

    SELECT CONCAT('Factura ', v_numero, ' registrada correctamente.') AS mensaje,
           v_numero AS numero_factura,
           @total_factura_generado AS total;
END //

/* =====================================================================
   11. sp_venta_anular  (TRANSACCIONAL)
   Las facturas nunca se borran, se anulan (regla 9).
   Validaciones: la factura existe y está vigente; el motivo no está vacío.
   Registra la fecha de anulación.
   ===================================================================== */
CREATE PROCEDURE sp_venta_anular(
    IN p_numero VARCHAR(20),
    IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_id_factura INT DEFAULT NULL;
    DECLARE v_estado     VARCHAR(10);
    DECLARE v_mensaje    VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_numero = TRIM(p_numero);
    SET p_motivo = TRIM(p_motivo);

    IF p_numero IS NULL OR p_numero = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-17] El número de factura es obligatorio.';
    END IF;

    SELECT id_factura, estado INTO v_id_factura, v_estado
    FROM factura WHERE numero = p_numero;

    IF v_id_factura IS NULL THEN
        SET v_mensaje = CONCAT('[E-VTA-14] No existe la factura ', p_numero, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF v_estado = 'ANULADA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-15] La factura ya estaba anulada.';
    END IF;

    IF p_motivo IS NULL OR p_motivo = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-16] El motivo de anulación es obligatorio.';
    END IF;

    START TRANSACTION;
    UPDATE factura
    SET estado = 'ANULADA', fecha_anulacion = NOW(), motivo_anulacion = p_motivo
    WHERE id_factura = v_id_factura;
    COMMIT;

    SELECT CONCAT('Factura ', p_numero, ' anulada correctamente.') AS mensaje;
END //

/* =====================================================================
   12. sp_venta_consultar
   Retorna el encabezado (fecha, sucursal, vendedor, cliente, método de
   pago, estado y total con fn_total_factura) y luego sus líneas de detalle.
   ===================================================================== */
CREATE PROCEDURE sp_venta_consultar(IN p_numero VARCHAR(20))
BEGIN
    DECLARE v_id_factura INT DEFAULT NULL;
    DECLARE v_mensaje    VARCHAR(255);

    SET p_numero = TRIM(p_numero);

    IF p_numero IS NULL OR p_numero = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '[E-VTA-17] El número de factura es obligatorio.';
    END IF;

    SELECT id_factura INTO v_id_factura FROM factura WHERE numero = p_numero;

    IF v_id_factura IS NULL THEN
        SET v_mensaje = CONCAT('[E-VTA-14] No existe la factura ', p_numero, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    -- Encabezado
    SELECT f.numero, f.fecha, f.hora,
           s.nombre AS sucursal,
           CONCAT(v.nombres, ' ', v.apellidos) AS vendedor,
           CONCAT(c.nombres, ' ', c.apellidos) AS cliente,
           c.nit,
           mp.nombre AS metodo_pago,
           f.estado,
           fn_total_factura(f.id_factura) AS total,
           f.fecha_anulacion, f.motivo_anulacion
    FROM factura f
    JOIN sucursal s     ON s.id_sucursal = f.id_sucursal
    JOIN vendedor v     ON v.id_vendedor = f.id_vendedor
    JOIN cliente c      ON c.id_cliente = f.id_cliente
    JOIN metodo_pago mp ON mp.id_metodo_pago = f.id_metodo_pago
    WHERE f.id_factura = v_id_factura;

    -- Líneas de detalle
    SELECT p.codigo, p.nombre AS producto, d.cantidad, d.precio_unitario, d.subtotal
    FROM detalle_factura d
    JOIN producto p ON p.id_producto = d.id_producto
    WHERE d.id_factura = v_id_factura
    ORDER BY d.id_detalle;
END //

DELIMITER ;

SELECT COUNT(*) AS procedimientos
FROM information_schema.routines
WHERE routine_schema = 'Proyecto_SistemasVentasGranilocas_V2' AND routine_type = 'PROCEDURE';
