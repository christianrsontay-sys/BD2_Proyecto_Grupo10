-- ##### ARCHIVO: 02_funciones.sql #####
/* =====================================================================
   02_funciones.sql
   Funciones reutilizables por procedimientos, triggers y el ETL.
     Obligatorias (6.3): fn_validar_nit, fn_validar_correo,
                         fn_total_factura, fn_descripcion_bitacora
     Adicionales:        fn_nombre_valido, fn_texto_valido, fn_id_municipio
   ===================================================================== */
USE Proyecto_SistemasVentasGranilocas_V2;

DROP FUNCTION IF EXISTS fn_validar_nit;
DROP FUNCTION IF EXISTS fn_validar_correo;
DROP FUNCTION IF EXISTS fn_nombre_valido;
DROP FUNCTION IF EXISTS fn_texto_valido;
DROP FUNCTION IF EXISTS fn_id_municipio;
DROP FUNCTION IF EXISTS fn_descripcion_bitacora;
DROP FUNCTION IF EXISTS fn_total_factura;
DELIMITER //

/* fn_validar_nit: solo dígitos (12345678) o dígitos-guion-un dígito (1234567-8).
   Retorna 1 si es válido, 0 si no. Se usa en el ETL y en los procedimientos de clientes. */
CREATE FUNCTION fn_validar_nit(p_nit VARCHAR(50))
RETURNS TINYINT
DETERMINISTIC
NO SQL
BEGIN
    IF p_nit IS NULL THEN
        RETURN 0;
    END IF;
    IF CHAR_LENGTH(p_nit) > 20 THEN      -- cliente.nit es VARCHAR(20)
        RETURN 0;
    END IF;
    IF p_nit NOT REGEXP '^[0-9]+(-[0-9])?$' THEN
        RETURN 0;
    END IF;
    RETURN 1;
END //

/* fn_validar_correo: formato usuario@dominio.ext, sin espacios. Retorna 1 / 0. */
CREATE FUNCTION fn_validar_correo(p_correo VARCHAR(255))
RETURNS TINYINT
DETERMINISTIC
NO SQL
BEGIN
    IF p_correo IS NULL THEN
        RETURN 0;
    END IF;
    IF CHAR_LENGTH(p_correo) > 150 THEN  -- cliente.correo es VARCHAR(150)
        RETURN 0;
    END IF;
    IF p_correo NOT REGEXP '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$' THEN
        RETURN 0;
    END IF;
    RETURN 1;
END //

/* fn_nombre_valido: nombres de personas (2 a 60 caracteres, letras/números y signos básicos) */
CREATE FUNCTION fn_nombre_valido(p_texto VARCHAR(200))
RETURNS TINYINT
DETERMINISTIC
NO SQL
BEGIN
    IF p_texto IS NULL THEN
        RETURN 0;
    END IF;
    IF CHAR_LENGTH(TRIM(p_texto)) NOT BETWEEN 2 AND 60 THEN
        RETURN 0;
    END IF;
    IF TRIM(p_texto) NOT REGEXP '^[[:alnum:] .,+&''-]+$' THEN
        RETURN 0;
    END IF;
    RETURN 1;
END //

/* fn_texto_valido: textos generales (p. ej. nombre de producto); largo máximo configurable */
CREATE FUNCTION fn_texto_valido(p_texto VARCHAR(200), p_max INT)
RETURNS TINYINT
DETERMINISTIC
NO SQL
BEGIN
    IF p_texto IS NULL THEN
        RETURN 0;
    END IF;
    IF CHAR_LENGTH(TRIM(p_texto)) NOT BETWEEN 2 AND p_max THEN
        RETURN 0;
    END IF;
    IF TRIM(p_texto) NOT REGEXP '^[[:alnum:] .,+&/()%#:''-]+$' THEN
        RETURN 0;
    END IF;
    RETURN 1;
END //

/* fn_id_municipio: busca un municipio por NOMBRE (o por su id si se envía un número).
   Retorna: el id_municipio, NULL si no existe, o -1 si el nombre existe en
   más de un departamento (en ese caso hay que enviar el id). */
CREATE FUNCTION fn_id_municipio(p_municipio VARCHAR(60))
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_cantidad INT DEFAULT 0;
    DECLARE v_id       INT DEFAULT NULL;

    SET p_municipio = TRIM(p_municipio);

    IF p_municipio IS NULL OR p_municipio = '' THEN
        RETURN NULL;
    END IF;

    IF p_municipio REGEXP '^[0-9]+$' THEN
        RETURN (SELECT id_municipio FROM municipio
                WHERE id_municipio = CAST(p_municipio AS UNSIGNED));
    END IF;

    SELECT COUNT(*), MIN(id_municipio) INTO v_cantidad, v_id
    FROM municipio
    WHERE nombre = p_municipio;

    IF v_cantidad > 1 THEN
        RETURN -1;
    END IF;

    RETURN v_id;   -- NULL si no existe
END //

/* fn_descripcion_bitacora: construye el texto descriptivo de la bitácora.
   Parámetros: tabla, operación, datos clave.
   Operaciones: INSERT, UPDATE, DELETE y ANULAR (solo para facturas).
   Ejemplo: fn_descripcion_bitacora('factura','ANULAR','107666. Motivo: error en el cliente')
            -> Se anuló la factura 107666. Motivo: error en el cliente */
CREATE FUNCTION fn_descripcion_bitacora(p_tabla VARCHAR(50), p_operacion VARCHAR(10), p_datos_clave VARCHAR(200))
RETURNS VARCHAR(255)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_datos VARCHAR(200);
    SET v_datos = COALESCE(p_datos_clave, '');

    RETURN LEFT(
        CASE p_operacion
            WHEN 'INSERT' THEN CONCAT('Se registró en ', p_tabla, ': ', v_datos)
            WHEN 'UPDATE' THEN CONCAT('Se modificó en ', p_tabla, ': ', v_datos)
            WHEN 'DELETE' THEN CONCAT('Se eliminó de ', p_tabla, ': ', v_datos)
            WHEN 'ANULAR' THEN CONCAT('Se anuló la factura ', v_datos)
            ELSE CONCAT(p_operacion, ' en ', p_tabla, ': ', v_datos)
        END, 255);
END //

/* fn_total_factura: suma de los subtotales del detalle (regla 8).
   Se usa en sp_venta_registrar y sp_venta_consultar. */
CREATE FUNCTION fn_total_factura(p_id_factura INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    RETURN COALESCE((SELECT SUM(subtotal)
                     FROM detalle_factura
                     WHERE id_factura = p_id_factura), 0);
END //

DELIMITER ;