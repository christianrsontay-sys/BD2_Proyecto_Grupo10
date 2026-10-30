-- ##### ARCHIVO: 01_modelo.sql #####
/* =====================================================================
   01_modelo.sql
   Modelo físico (3FN). Orden de creación respetando las llaves foráneas.
   ===================================================================== */
USE Proyecto_SistemasVentasGranilocas_V2;

CREATE TABLE departamento (
    id_departamento INT AUTO_INCREMENT PRIMARY KEY,
    nombre          VARCHAR(60) NOT NULL,
    CONSTRAINT uq_departamento_nombre UNIQUE (nombre)
);

CREATE TABLE municipio (
    id_municipio    INT AUTO_INCREMENT PRIMARY KEY,
    nombre          VARCHAR(60) NOT NULL,
    id_departamento INT NOT NULL,
    CONSTRAINT uq_municipio UNIQUE (nombre, id_departamento),
    INDEX idx_municipio_departamento (id_departamento),
    CONSTRAINT fk_municipio_departamento FOREIGN KEY (id_departamento)
        REFERENCES departamento (id_departamento)
);

CREATE TABLE sucursal (
    id_sucursal  INT AUTO_INCREMENT PRIMARY KEY,
    codigo       VARCHAR(10)  NOT NULL,
    nombre       VARCHAR(60)  NOT NULL,
    direccion    VARCHAR(150) NOT NULL,
    id_municipio INT NOT NULL,
    CONSTRAINT uq_sucursal_codigo UNIQUE (codigo),
    INDEX idx_sucursal_municipio (id_municipio),
    CONSTRAINT fk_sucursal_municipio FOREIGN KEY (id_municipio)
        REFERENCES municipio (id_municipio)
);

CREATE TABLE categoria (
    id_categoria INT AUTO_INCREMENT PRIMARY KEY,
    nombre       VARCHAR(60) NOT NULL,
    CONSTRAINT uq_categoria_nombre UNIQUE (nombre)
);

CREATE TABLE marca (
    id_marca INT AUTO_INCREMENT PRIMARY KEY,
    nombre   VARCHAR(60) NOT NULL,
    CONSTRAINT uq_marca_nombre UNIQUE (nombre)
);

CREATE TABLE producto (
    id_producto    INT AUTO_INCREMENT PRIMARY KEY,
    codigo         VARCHAR(10)   NOT NULL,
    nombre         VARCHAR(120)  NOT NULL,
    id_categoria   INT           NOT NULL,
    id_marca       INT           NOT NULL,
    precio_actual  DECIMAL(12,2) NOT NULL,
    estado         VARCHAR(10)   NOT NULL DEFAULT 'ACTIVO',
    fecha_registro DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_producto_codigo UNIQUE (codigo),
    INDEX idx_producto_categoria (id_categoria),
    INDEX idx_producto_marca (id_marca),
    INDEX idx_producto_nombre (nombre),
    CONSTRAINT ck_producto_precio CHECK (precio_actual > 0),
    CONSTRAINT ck_producto_estado CHECK (estado IN ('ACTIVO', 'INACTIVO')),
    CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria) REFERENCES categoria (id_categoria),
    CONSTRAINT fk_producto_marca     FOREIGN KEY (id_marca)     REFERENCES marca (id_marca)
);

CREATE TABLE vendedor (
    id_vendedor INT AUTO_INCREMENT PRIMARY KEY,
    codigo      VARCHAR(10) NOT NULL,
    nombres     VARCHAR(60) NOT NULL,
    apellidos   VARCHAR(60) NOT NULL,
    id_sucursal INT NOT NULL,
    estado      VARCHAR(10) NOT NULL DEFAULT 'ACTIVO',
    CONSTRAINT uq_vendedor_codigo UNIQUE (codigo),
    INDEX idx_vendedor_sucursal (id_sucursal),
    CONSTRAINT fk_vendedor_sucursal FOREIGN KEY (id_sucursal)
        REFERENCES sucursal (id_sucursal),
    CONSTRAINT ck_vendedor_estado CHECK (estado IN ('ACTIVO','INACTIVO')),
    -- Necesario para la FK compuesta desde factura (regla 3)
    CONSTRAINT uq_vendedor_sucursal UNIQUE (id_vendedor, id_sucursal)
);

CREATE TABLE cliente (
    id_cliente       INT AUTO_INCREMENT PRIMARY KEY,
    nit              VARCHAR(20)  NOT NULL,
    nombres          VARCHAR(60)  NOT NULL,
    apellidos        VARCHAR(60)  NOT NULL,
    genero           CHAR(1)      NULL,
    fecha_nacimiento DATE         NULL,
    correo           VARCHAR(150) NOT NULL,
    telefono         VARCHAR(20)  NULL,
    direccion        VARCHAR(200) NULL,
    id_municipio     INT NOT NULL,
    estado           VARCHAR(10)  NOT NULL DEFAULT 'ACTIVO',
    CONSTRAINT fk_cliente_municipio FOREIGN KEY (id_municipio)
        REFERENCES municipio (id_municipio),
    CONSTRAINT uq_cliente_nit    UNIQUE (nit),
    CONSTRAINT uq_cliente_correo UNIQUE (correo),
    INDEX idx_cliente_municipio (id_municipio),
    INDEX idx_cliente_apellidos (apellidos, nombres),
    -- MySQL no permite funciones propias dentro de un CHECK: se usa REGEXP directo
    CONSTRAINT ck_cliente_nit    CHECK (REGEXP_LIKE(nit, '^[0-9]+(-[0-9])?$')),
    CONSTRAINT ck_cliente_correo CHECK (REGEXP_LIKE(correo, '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$')),
    CONSTRAINT ck_cliente_genero CHECK (genero IN ('M','F')),
    CONSTRAINT ck_cliente_estado CHECK (estado IN ('ACTIVO','INACTIVO'))
);

CREATE TABLE metodo_pago (
    id_metodo_pago INT AUTO_INCREMENT PRIMARY KEY,
    nombre         VARCHAR(30) NOT NULL,
    CONSTRAINT uq_metodo_pago_nombre UNIQUE (nombre)
);

INSERT INTO metodo_pago (nombre) VALUES ('Efectivo'), ('Tarjeta'), ('Transferencia');

CREATE TABLE factura (
    id_factura       INT AUTO_INCREMENT PRIMARY KEY,
    numero           VARCHAR(20)   NOT NULL,
    fecha            DATE          NOT NULL,
    hora             TIME          NULL,
    id_sucursal      INT           NOT NULL,
    id_vendedor      INT           NOT NULL,
    id_cliente       INT           NOT NULL,
    id_metodo_pago   INT           NOT NULL,
    total            DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    estado           VARCHAR(10)   NOT NULL DEFAULT 'EMITIDA',
    fecha_anulacion  DATETIME      NULL,
    motivo_anulacion VARCHAR(255)  NULL,
    CONSTRAINT uq_factura_numero UNIQUE (numero),
    CONSTRAINT fk_factura_sucursal FOREIGN KEY (id_sucursal)
        REFERENCES sucursal (id_sucursal),
    -- FK compuesta: el vendedor solo puede facturar en SU sucursal (regla 3)
    CONSTRAINT fk_factura_vendedor_sucursal FOREIGN KEY (id_vendedor, id_sucursal)
        REFERENCES vendedor (id_vendedor, id_sucursal),
    CONSTRAINT fk_factura_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente),
    CONSTRAINT fk_factura_metodo_pago FOREIGN KEY (id_metodo_pago)
        REFERENCES metodo_pago (id_metodo_pago),
    CONSTRAINT ck_factura_total  CHECK (total >= 0),
    CONSTRAINT ck_factura_estado CHECK (estado IN ('EMITIDA', 'ANULADA')),
    CONSTRAINT ck_factura_anulacion CHECK (
        (estado = 'EMITIDA' AND fecha_anulacion IS NULL AND motivo_anulacion IS NULL)
        OR
        (estado = 'ANULADA' AND fecha_anulacion IS NOT NULL AND motivo_anulacion IS NOT NULL)
    ),
    INDEX idx_factura_fecha    (fecha),
    INDEX idx_factura_cliente  (id_cliente),
    INDEX idx_factura_sucursal (id_sucursal),
    INDEX idx_factura_vendedor (id_vendedor, id_sucursal),
    INDEX idx_factura_metodo_pago (id_metodo_pago),
    INDEX idx_factura_estado (estado)
);

CREATE TABLE detalle_factura (
    id_detalle      INT AUTO_INCREMENT PRIMARY KEY,
    id_factura      INT           NOT NULL,
    id_producto     INT           NOT NULL,
    cantidad        INT           NOT NULL,
    precio_unitario DECIMAL(12,2) NOT NULL,     -- precio al momento de la venta (regla 6)
    subtotal        DECIMAL(12,2) NOT NULL,
    CONSTRAINT fk_detalle_factura  FOREIGN KEY (id_factura)
        REFERENCES factura (id_factura),
    CONSTRAINT fk_detalle_producto FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto),
    CONSTRAINT uq_detalle_factura_producto UNIQUE (id_factura, id_producto),   -- regla 2
    CONSTRAINT ck_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_detalle_precio   CHECK (precio_unitario >= 0),
    CONSTRAINT ck_detalle_subtotal CHECK (subtotal = precio_unitario * cantidad),
    INDEX idx_detalle_producto (id_producto)
);

CREATE TABLE etl_control (
    id_etl           INT AUTO_INCREMENT PRIMARY KEY,
    fecha_inicio     DATETIME     NOT NULL,
    fecha_fin        DATETIME     NULL,
    filas_leidas     INT          NULL,
    filas_insertadas VARCHAR(500) NULL,
    estado           VARCHAR(10)  NOT NULL,
    mensaje          TEXT         NULL,
    CONSTRAINT ck_etl_estado CHECK (estado IN ('EXITOSO', 'FALLIDO'))
);

CREATE TABLE bitacora (
    id_bitacora      INT AUTO_INCREMENT PRIMARY KEY,
    fecha_hora       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario          VARCHAR(100) NOT NULL,
    tabla            VARCHAR(50)  NOT NULL,
    operacion        VARCHAR(10)  NOT NULL,
    id_registro      INT          NOT NULL,
    descripcion      VARCHAR(255) NOT NULL,
    datos_anteriores JSON NULL,
    datos_nuevos     JSON NULL,
    CONSTRAINT ck_bitacora_operacion CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
    INDEX idx_bitacora_tabla_registro (tabla, id_registro),
    INDEX idx_bitacora_fecha (fecha_hora)
);