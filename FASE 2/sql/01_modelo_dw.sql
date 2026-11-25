/* =====================================================================
   01_modelo_dw.sql
   Crea la base dw_ventas: esquema en estrella (una tabla de hechos y seis
   dimensiones desnormalizadas) y la tabla de control de cargas.

   Grano de fact_ventas: UNA FILA POR CADA LINEA DE FACTURA.
   Cada dimension tiene una llave sustituta (sk_...) como PRIMARY KEY y
   conserva la llave natural del sistema operativo (UNIQUE).
   Se puede ejecutar varias veces: elimina y vuelve a crear la base.
   ===================================================================== */
DROP DATABASE IF EXISTS dw_ventas;

CREATE DATABASE dw_ventas
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;   -- el mismo de la base de la Fase 1

USE dw_ventas;

-- ---------------------------------------------------------------------
-- DIMENSION TIEMPO     Jerarquia: anio > trimestre > mes > dia
-- ---------------------------------------------------------------------
CREATE TABLE dim_tiempo (
    sk_tiempo      INT AUTO_INCREMENT PRIMARY KEY,
    fecha          DATE        NOT NULL,                 -- llave natural
    anio           SMALLINT    NOT NULL,
    trimestre      TINYINT     NOT NULL,
    mes            TINYINT     NOT NULL,
    nombre_mes     VARCHAR(15) NOT NULL,
    dia            TINYINT     NOT NULL,
    dia_semana     VARCHAR(15) NOT NULL,
    anio_trimestre CHAR(7)     NOT NULL,                 -- ej. 2024-T1
    anio_mes       CHAR(7)     NOT NULL,                 -- ej. 2024-03
    CONSTRAINT uq_dim_tiempo_fecha UNIQUE (fecha),
    INDEX idx_dim_tiempo_anio (anio, trimestre, mes)
);

-- ---------------------------------------------------------------------
-- DIMENSION PRODUCTO   Jerarquia: categoria > marca > producto
-- ---------------------------------------------------------------------
CREATE TABLE dim_producto (
    sk_producto     INT AUTO_INCREMENT PRIMARY KEY,
    codigo_producto VARCHAR(10)  NOT NULL,               -- llave natural
    nombre_producto VARCHAR(120) NOT NULL,
    categoria       VARCHAR(60)  NOT NULL,
    marca           VARCHAR(60)  NOT NULL,
    CONSTRAINT uq_dim_producto_codigo UNIQUE (codigo_producto),
    INDEX idx_dim_producto_categoria (categoria, marca)
);

-- ---------------------------------------------------------------------
-- DIMENSION CLIENTE    Jerarquia: departamento > municipio > cliente
-- (ubicacion registrada en la ficha del cliente)
-- ---------------------------------------------------------------------
CREATE TABLE dim_cliente (
    sk_cliente      INT AUTO_INCREMENT PRIMARY KEY,
    nit             VARCHAR(20)  NOT NULL,               -- llave natural
    nombre_completo VARCHAR(125) NOT NULL,
    genero          CHAR(1)      NULL,
    municipio       VARCHAR(60)  NOT NULL,
    departamento    VARCHAR(60)  NOT NULL,
    CONSTRAINT uq_dim_cliente_nit UNIQUE (nit),
    INDEX idx_dim_cliente_departamento (departamento, municipio)
);

-- ---------------------------------------------------------------------
-- DIMENSION UBICACION  Jerarquia: departamento > municipio > sucursal
-- (sucursal donde se realizo la factura)
-- ---------------------------------------------------------------------
CREATE TABLE dim_ubicacion (
    sk_ubicacion    INT AUTO_INCREMENT PRIMARY KEY,
    codigo_sucursal VARCHAR(10) NOT NULL,                -- llave natural
    nombre_sucursal VARCHAR(60) NOT NULL,
    municipio       VARCHAR(60) NOT NULL,
    departamento    VARCHAR(60) NOT NULL,
    CONSTRAINT uq_dim_ubicacion_codigo UNIQUE (codigo_sucursal),
    INDEX idx_dim_ubicacion_departamento (departamento, municipio)
);

-- ---------------------------------------------------------------------
-- DIMENSION VENDEDOR   Jerarquia: sucursal > vendedor
-- ---------------------------------------------------------------------
CREATE TABLE dim_vendedor (
    sk_vendedor     INT AUTO_INCREMENT PRIMARY KEY,
    codigo_vendedor VARCHAR(10)  NOT NULL,               -- llave natural
    nombre_completo VARCHAR(125) NOT NULL,
    codigo_sucursal VARCHAR(10)  NOT NULL,               -- sucursal a la que pertenece
    nombre_sucursal VARCHAR(60)  NOT NULL,
    CONSTRAINT uq_dim_vendedor_codigo UNIQUE (codigo_vendedor),
    INDEX idx_dim_vendedor_sucursal (codigo_sucursal)
);

-- ---------------------------------------------------------------------
-- DIMENSION METODO DE PAGO
-- ---------------------------------------------------------------------
CREATE TABLE dim_metodo_pago (
    sk_metodo_pago INT AUTO_INCREMENT PRIMARY KEY,
    nombre_metodo  VARCHAR(30) NOT NULL,                 -- llave natural
    CONSTRAINT uq_dim_metodo_pago_nombre UNIQUE (nombre_metodo)
);

-- ---------------------------------------------------------------------
-- TABLA DE HECHOS
-- Medidas: cantidad, precio_unitario y monto_linea.
-- vigente: 1 = factura vigente, 0 = factura anulada (las lineas de las
-- anuladas se conservan; los reportes solo suman las vigentes).
-- ---------------------------------------------------------------------
CREATE TABLE fact_ventas (
    sk_tiempo      INT           NOT NULL,
    sk_producto    INT           NOT NULL,
    sk_cliente     INT           NOT NULL,
    sk_ubicacion   INT           NOT NULL,
    sk_vendedor    INT           NOT NULL,
    sk_metodo_pago INT           NOT NULL,
    numero_factura VARCHAR(20)   NOT NULL,
    linea          INT           NOT NULL,
    vigente        TINYINT(1)    NOT NULL,
    cantidad       INT           NOT NULL,
    precio_unitario DECIMAL(12,2) NOT NULL,
    monto_linea    DECIMAL(12,2) NOT NULL,
    PRIMARY KEY (numero_factura, linea),
    CONSTRAINT ck_fact_vigente CHECK (vigente IN (0, 1)),
    CONSTRAINT fk_fact_tiempo      FOREIGN KEY (sk_tiempo)      REFERENCES dim_tiempo (sk_tiempo),
    CONSTRAINT fk_fact_producto    FOREIGN KEY (sk_producto)    REFERENCES dim_producto (sk_producto),
    CONSTRAINT fk_fact_cliente     FOREIGN KEY (sk_cliente)     REFERENCES dim_cliente (sk_cliente),
    CONSTRAINT fk_fact_ubicacion   FOREIGN KEY (sk_ubicacion)   REFERENCES dim_ubicacion (sk_ubicacion),
    CONSTRAINT fk_fact_vendedor    FOREIGN KEY (sk_vendedor)    REFERENCES dim_vendedor (sk_vendedor),
    CONSTRAINT fk_fact_metodo_pago FOREIGN KEY (sk_metodo_pago) REFERENCES dim_metodo_pago (sk_metodo_pago),
    INDEX idx_fact_vigente_tiempo (vigente, sk_tiempo),
    INDEX idx_fact_vigente_ubicacion (vigente, sk_ubicacion)
);

-- ---------------------------------------------------------------------
-- CONTROL DE CARGAS: una fila por cada ejecucion de sp_dw_cargar
-- ---------------------------------------------------------------------
CREATE TABLE dw_control (
    id_control     INT AUTO_INCREMENT PRIMARY KEY,
    fecha_inicio   DATETIME    NOT NULL,
    fecha_fin      DATETIME    NULL,
    filas_leidas   INT         NULL,        -- lineas leidas del origen
    filas_cargadas INT         NULL,        -- filas cargadas en fact_ventas
    estado         VARCHAR(10) NOT NULL,    -- EXITOSO o FALLIDO
    mensaje        TEXT        NULL,        -- mensaje de error si fallo
    CONSTRAINT ck_dw_control_estado CHECK (estado IN ('EXITOSO', 'FALLIDO'))
);
