const pool = require('../config/database');

const errorValidacion = (mensaje) => {
    const error = new Error(mensaje);
    error.status = 400;
    return error;
};

const obtenerEntero = (query, nombre, minimo, maximo) => {
    if (query[nombre] === undefined) return undefined;

    const valor = Number(query[nombre]);

    if (!Number.isInteger(valor) ||
        (minimo !== undefined && valor < minimo) ||
        (maximo !== undefined && valor > maximo)) {
        throw errorValidacion(`El parámetro ${nombre} no es válido.`);
    }

    return valor;
};

const obtenerTexto = (query, nombre) => {
    if (query[nombre] === undefined) return undefined;

    const valor = String(query[nombre]).trim();

    if (!valor) {
        throw errorValidacion(`El parámetro ${nombre} no puede estar vacío.`);
    }

    return valor;
};

const obtenerAnio = (query) =>
    obtenerEntero(query, 'anio', 1, 9999);

const filtrosAnioSucursal = (query, alias = 'dt') => {
    const anio = obtenerAnio(query);
    const sucursal = obtenerTexto(query, 'sucursal');

    const condiciones = [];
    const parametros = [];

    if (anio !== undefined) {
        condiciones.push(`${alias}.anio = ?`);
        parametros.push(anio);
    }

    if (sucursal !== undefined) {
        condiciones.push(`u.codigo_sucursal = ?`);
        parametros.push(sucursal);
    }

    return { condiciones, parametros, anio, sucursal };
};

const ejecutar = (reporte, consulta) => async (req, res) => {
    try {
        const resultado = await consulta(req);

        res.json({
            reporte,
            filtros: resultado.filtros,
            datos: resultado.datos
        });
    } catch (error) {
        console.error(`Error en reporte ${reporte}:`, error.message);

        res.status(error.status || 500).json({
            error: error.status === 400
                ? error.message
                : 'Ocurrió un error al generar el reporte.'
        });
    }
};

const convertirNumeros = (rows, campos) =>
    rows.map(row => {
        const nuevo = { ...row };

        campos.forEach(campo => {
            if (nuevo[campo] !== null && nuevo[campo] !== undefined) {
                nuevo[campo] = Number(nuevo[campo]);
            }
        });

        return nuevo;
    });

const construirWhere = (condiciones) =>
    condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '';


// 1. INDICADORES

const indicadores = ejecutar('indicadores', async (req) => {
    const { condiciones, parametros, anio, sucursal } =
        filtrosAnioSucursal(req.query);

    const sql = `
        SELECT
            ROUND(COALESCE(SUM(f.monto_linea), 0), 2) AS ventas,
            COUNT(DISTINCT f.numero_factura) AS facturas,
            COALESCE(SUM(f.cantidad), 0) AS unidades,
            ROUND(
                COALESCE(
                    SUM(f.monto_linea) /
                    NULLIF(COUNT(DISTINCT f.numero_factura), 0),
                    0
                ), 2
            ) AS ticket_promedio,
            COUNT(DISTINCT f.sk_cliente) AS clientes
        FROM dw_ventas.fact_ventas f
        LEFT JOIN dw_ventas.dim_tiempo dt
            ON f.sk_tiempo = dt.sk_tiempo
        LEFT JOIN dw_ventas.dim_ubicacion u
            ON f.sk_ubicacion = u.sk_ubicacion
        WHERE f.vigente = 1
        ${condiciones.length ? 'AND ' + condiciones.join(' AND ') : ''}
    `;

    const [rows] = await pool.query(sql, parametros);

    return {
        filtros: { anio, sucursal },
        datos: convertirNumeros(rows, [
            'ventas', 'facturas', 'unidades',
            'ticket_promedio', 'clientes'
        ])
    };
});


// 2. VENTAS POR TIEMPO

const ventasTiempo = ejecutar('ventas-tiempo', async (req) => {
    const nivel = obtenerTexto(req.query, 'nivel');

    if (!['anio', 'trimestre', 'mes'].includes(nivel)) {
        throw errorValidacion(
            'El parámetro nivel debe ser anio, trimestre o mes.'
        );
    }

    const anio = obtenerAnio(req.query);
    const trimestre = obtenerEntero(req.query, 'trimestre', 1, 4);
    const sucursal = obtenerTexto(req.query, 'sucursal');

    if (trimestre !== undefined && anio === undefined) {
        throw errorValidacion(
            'El parámetro trimestre requiere especificar anio.'
        );
    }

    if (nivel !== 'trimestre' && trimestre !== undefined) {
        throw errorValidacion(
            'El parámetro trimestre solo se utiliza con nivel trimestre.'
        );
    }

    const condiciones = ['f.vigente = 1'];
    const parametros = [];

    if (anio !== undefined) {
        condiciones.push('dt.anio = ?');
        parametros.push(anio);
    }

    if (trimestre !== undefined) {
        condiciones.push('dt.trimestre = ?');
        parametros.push(trimestre);
    }

    if (sucursal !== undefined) {
        condiciones.push('u.codigo_sucursal = ?');
        parametros.push(sucursal);
    }

    let periodo;
    let agrupacion;

    if (nivel === 'anio') {
        periodo = 'CAST(dt.anio AS CHAR)';
        agrupacion = 'dt.anio';
    } else if (nivel === 'trimestre') {
        periodo = "CONCAT(dt.anio, '-T', dt.trimestre)";
        agrupacion = 'dt.anio, dt.trimestre';
    } else {
        periodo = "CONCAT(dt.anio, '-', LPAD(dt.mes, 2, '0'))";
        agrupacion = 'dt.anio, dt.mes';
    }

    const sql = `
        SELECT
            ${periodo} AS periodo,
            ROUND(SUM(f.monto_linea), 2) AS ventas,
            COUNT(DISTINCT f.numero_factura) AS facturas,
            SUM(f.cantidad) AS unidades
        FROM dw_ventas.fact_ventas f
        INNER JOIN dw_ventas.dim_tiempo dt
            ON f.sk_tiempo = dt.sk_tiempo
        INNER JOIN dw_ventas.dim_ubicacion u
            ON f.sk_ubicacion = u.sk_ubicacion
        WHERE ${condiciones.join(' AND ')}
        GROUP BY ${agrupacion}
        ORDER BY ${agrupacion}
    `;

    const [rows] = await pool.query(sql, parametros);

    return {
        filtros: { nivel, anio, trimestre, sucursal },
        datos: convertirNumeros(rows, [
            'ventas', 'facturas', 'unidades'
        ])
    };
});


// 3. VENTAS POR UBICACIÓN

const ventasUbicacion = ejecutar('ventas-ubicacion', async (req) => {
    const nivel = obtenerTexto(req.query, 'nivel');

    if (!['departamento', 'municipio', 'sucursal'].includes(nivel)) {
        throw errorValidacion(
            'El nivel debe ser departamento, municipio o sucursal.'
        );
    }

    const departamento = obtenerTexto(req.query, 'departamento');
    const municipio = obtenerTexto(req.query, 'municipio');
    const anio = obtenerAnio(req.query);

    const condiciones = ['f.vigente = 1'];
    const parametros = [];

    if (departamento !== undefined) {
        condiciones.push('u.departamento = ?');
        parametros.push(departamento);
    }

    if (municipio !== undefined) {
        condiciones.push('u.municipio = ?');
        parametros.push(municipio);
    }

    if (anio !== undefined) {
        condiciones.push('dt.anio = ?');
        parametros.push(anio);
    }

    let campos = 'u.departamento';
    let agrupacion = 'u.departamento';

    if (nivel === 'municipio') {
        campos += ', u.municipio';
        agrupacion += ', u.municipio';
    }

    if (nivel === 'sucursal') {
        campos += ', u.municipio, u.codigo_sucursal AS sucursal, u.nombre_sucursal';
        agrupacion += ', u.municipio, u.codigo_sucursal, u.nombre_sucursal';
    }

    const sql = `
        SELECT
            ${campos},
            ROUND(SUM(f.monto_linea), 2) AS ventas,
            COUNT(DISTINCT f.numero_factura) AS facturas,
            SUM(f.cantidad) AS unidades
        FROM dw_ventas.fact_ventas f
        INNER JOIN dw_ventas.dim_tiempo dt
            ON f.sk_tiempo = dt.sk_tiempo
        INNER JOIN dw_ventas.dim_ubicacion u
            ON f.sk_ubicacion = u.sk_ubicacion
        WHERE ${condiciones.join(' AND ')}
        GROUP BY ${agrupacion}
        ORDER BY ventas DESC
    `;

    const [rows] = await pool.query(sql, parametros);

    return {
        filtros: { nivel, departamento, municipio, anio },
        datos: convertirNumeros(rows, [
            'ventas', 'facturas', 'unidades'
        ])
    };
});


// 4. VENTAS POR PRODUCTO

const ventasProducto = ejecutar('ventas-producto', async (req) => {
    const nivel = obtenerTexto(req.query, 'nivel');

    if (!['categoria', 'marca'].includes(nivel)) {
        throw errorValidacion(
            'El nivel debe ser categoria o marca.'
        );
    }

    const categoria = obtenerTexto(req.query, 'categoria');
    const anio = obtenerAnio(req.query);

    const condiciones = ['f.vigente = 1'];
    const parametros = [];

    if (categoria !== undefined) {
        condiciones.push('p.categoria = ?');
        parametros.push(categoria);
    }

    if (anio !== undefined) {
        condiciones.push('dt.anio = ?');
        parametros.push(anio);
    }

    const campos = nivel === 'marca'
        ? 'p.categoria, p.marca'
        : 'p.categoria';

    const agrupacion = nivel === 'marca'
        ? 'p.categoria, p.marca'
        : 'p.categoria';

    const sql = `
        WITH resumen AS (
            SELECT
                ${campos},
                SUM(f.monto_linea) AS ventas,
                SUM(f.cantidad) AS unidades
            FROM dw_ventas.fact_ventas f
            INNER JOIN dw_ventas.dim_producto p
                ON f.sk_producto = p.sk_producto
            INNER JOIN dw_ventas.dim_tiempo dt
                ON f.sk_tiempo = dt.sk_tiempo
            WHERE ${condiciones.join(' AND ')}
            GROUP BY ${agrupacion}
        )
        SELECT
            *,
            ROUND(
                ventas / NULLIF(SUM(ventas) OVER (), 0) * 100,
                2
            ) AS participacion
        FROM resumen
        ORDER BY ventas DESC
    `;

    const [rows] = await pool.query(sql, parametros);

    return {
        filtros: { nivel, categoria, anio },
        datos: convertirNumeros(rows, [
            'ventas', 'unidades', 'participacion'
        ])
    };
});


// 5. TOP PRODUCTOS

const topProductos = ejecutar('top-productos', async (req) => {
    const criterio = req.query.criterio || 'monto';

    if (!['monto', 'unidades'].includes(criterio)) {
        throw errorValidacion(
            'El criterio debe ser monto o unidades.'
        );
    }

    const limite = obtenerEntero(req.query, 'limite', 1, 100) ?? 10;
    const anio = obtenerAnio(req.query);
    const categoria = obtenerTexto(req.query, 'categoria');

    const condiciones = ['f.vigente = 1'];
    const parametros = [];

    if (anio !== undefined) {
        condiciones.push('dt.anio = ?');
        parametros.push(anio);
    }

    if (categoria !== undefined) {
        condiciones.push('p.categoria = ?');
        parametros.push(categoria);
    }

    const orden = criterio === 'monto'
        ? 'ventas DESC'
        : 'unidades DESC';

    const sql = `
        SELECT
            p.codigo_producto AS codigo,
            p.nombre_producto AS nombre,
            p.categoria,
            p.marca,
            ROUND(SUM(f.monto_linea), 2) AS ventas,
            SUM(f.cantidad) AS unidades
        FROM dw_ventas.fact_ventas f
        INNER JOIN dw_ventas.dim_producto p
            ON f.sk_producto = p.sk_producto
        INNER JOIN dw_ventas.dim_tiempo dt
            ON f.sk_tiempo = dt.sk_tiempo
        WHERE ${condiciones.join(' AND ')}
        GROUP BY
            p.sk_producto,
            p.codigo_producto,
            p.nombre_producto,
            p.categoria,
            p.marca
        ORDER BY ${orden}, p.codigo_producto ASC
        LIMIT ?
    `;

    parametros.push(limite);

    const [rows] = await pool.query(sql, parametros);

    const datos = convertirNumeros(rows, ['ventas', 'unidades'])
        .map((row, index) => ({
            posicion: index + 1,
            ...row
        }));

    return {
        filtros: { criterio, limite, anio, categoria },
        datos
    };
});


// 6. VENDEDORES

const vendedores = ejecutar('vendedores', async (req) => {
    const anio = obtenerAnio(req.query);
    const sucursal = obtenerTexto(req.query, 'sucursal');
    const limite = obtenerEntero(req.query, 'limite', 1, 100) ?? 10;

    const condiciones = ['f.vigente = 1'];
    const parametros = [];

    if (anio !== undefined) {
        condiciones.push('dt.anio = ?');
        parametros.push(anio);
    }

    if (sucursal !== undefined) {
        condiciones.push('v.codigo_sucursal = ?');
        parametros.push(sucursal);
    }

    const sql = `
        SELECT
            v.codigo_vendedor AS codigo,
            v.nombre_completo AS nombre,
            v.codigo_sucursal AS sucursal,
            ROUND(SUM(f.monto_linea), 2) AS ventas,
            COUNT(DISTINCT f.numero_factura) AS facturas,
            ROUND(
                SUM(f.monto_linea) /
                NULLIF(COUNT(DISTINCT f.numero_factura), 0),
                2
            ) AS ticket_promedio
        FROM dw_ventas.fact_ventas f
        INNER JOIN dw_ventas.dim_vendedor v
            ON f.sk_vendedor = v.sk_vendedor
        INNER JOIN dw_ventas.dim_tiempo dt
            ON f.sk_tiempo = dt.sk_tiempo
        WHERE ${condiciones.join(' AND ')}
        GROUP BY
            v.sk_vendedor,
            v.codigo_vendedor,
            v.nombre_completo,
            v.codigo_sucursal
        ORDER BY ventas DESC, v.codigo_vendedor ASC
        LIMIT ?
    `;

    parametros.push(limite);

    const [rows] = await pool.query(sql, parametros);

    const datos = convertirNumeros(rows, [
        'ventas', 'facturas', 'ticket_promedio'
    ]).map((row, index) => ({
        posicion: index + 1,
        ...row
    }));

    return {
        filtros: { anio, sucursal, limite },
        datos
    };
});


// 7. CLIENTES

const clientes = ejecutar('clientes', async (req) => {
    const anio = obtenerAnio(req.query);
    const departamento = obtenerTexto(req.query, 'departamento');
    const limite = obtenerEntero(req.query, 'limite', 1, 100) ?? 10;

    const condiciones = ['f.vigente = 1'];
    const parametros = [];

    if (anio !== undefined) {
        condiciones.push('dt.anio = ?');
        parametros.push(anio);
    }

    if (departamento !== undefined) {
        condiciones.push('c.departamento = ?');
        parametros.push(departamento);
    }

    const sql = `
        SELECT
            c.nit,
            c.nombre_completo AS nombre,
            c.departamento,
            ROUND(SUM(f.monto_linea), 2) AS ventas,
            COUNT(DISTINCT f.numero_factura) AS facturas
        FROM dw_ventas.fact_ventas f
        INNER JOIN dw_ventas.dim_cliente c
            ON f.sk_cliente = c.sk_cliente
        INNER JOIN dw_ventas.dim_tiempo dt
            ON f.sk_tiempo = dt.sk_tiempo
        WHERE ${condiciones.join(' AND ')}
        GROUP BY
            c.sk_cliente,
            c.nit,
            c.nombre_completo,
            c.departamento
        ORDER BY ventas DESC, c.nit ASC
        LIMIT ?
    `;

    parametros.push(limite);

    const [rows] = await pool.query(sql, parametros);

    const datos = convertirNumeros(rows, [
        'ventas', 'facturas'
    ]).map((row, index) => ({
        posicion: index + 1,
        ...row
    }));

    return {
        filtros: { anio, departamento, limite },
        datos
    };
});


// 8. COMPARATIVO ANUAL

const comparativo = ejecutar('comparativo', async (req) => {
    const anio = obtenerAnio(req.query);

    if (anio === undefined) {
        throw errorValidacion(
            'El parámetro anio es obligatorio.'
        );
    }

    const sucursal = obtenerTexto(req.query, 'sucursal');

    const condiciones = [
        'f.vigente = 1',
        'dt.anio IN (?, ?)'
    ];

    const parametros = [anio - 1, anio];

    if (sucursal !== undefined) {
        condiciones.push('u.codigo_sucursal = ?');
        parametros.push(sucursal);
    }

    const sql = `
        SELECT
            dt.anio,
            dt.mes,
            SUM(f.monto_linea) AS ventas
        FROM dw_ventas.fact_ventas f
        INNER JOIN dw_ventas.dim_tiempo dt
            ON f.sk_tiempo = dt.sk_tiempo
        INNER JOIN dw_ventas.dim_ubicacion u
            ON f.sk_ubicacion = u.sk_ubicacion
        WHERE ${condiciones.join(' AND ')}
        GROUP BY dt.anio, dt.mes
    `;

    const [rows] = await pool.query(sql, parametros);

    const mapa = {};

    rows.forEach(row => {
        mapa[`${row.anio}-${row.mes}`] = Number(row.ventas || 0);
    });

    const datos = [];

    for (let mes = 1; mes <= 12; mes++) {
        const anterior = mapa[`${anio - 1}-${mes}`] || 0;
        const actual = mapa[`${anio}-${mes}`] || 0;

        datos.push({
            mes,
            ventas_anterior: Number(anterior.toFixed(2)),
            ventas_actual: Number(actual.toFixed(2)),
            crecimiento: anterior === 0
                ? null
                : Number((((actual - anterior) / anterior) * 100).toFixed(2))
        });
    }

    return {
        filtros: { anio, sucursal },
        datos
    };
});


// 9. MÉTODOS DE PAGO

const metodosPago = ejecutar('metodos-pago', async (req) => {
    const { condiciones, parametros, anio, sucursal } =
        filtrosAnioSucursal(req.query);

    const sql = `
        WITH resumen AS (
            SELECT
                mp.nombre_metodo AS metodo,
                SUM(f.monto_linea) AS ventas,
                COUNT(DISTINCT f.numero_factura) AS facturas
            FROM dw_ventas.fact_ventas f
            INNER JOIN dw_ventas.dim_metodo_pago mp
                ON f.sk_metodo_pago = mp.sk_metodo_pago
            INNER JOIN dw_ventas.dim_tiempo dt
                ON f.sk_tiempo = dt.sk_tiempo
            INNER JOIN dw_ventas.dim_ubicacion u
                ON f.sk_ubicacion = u.sk_ubicacion
            WHERE f.vigente = 1
            ${condiciones.length ? 'AND ' + condiciones.join(' AND ') : ''}
            GROUP BY mp.sk_metodo_pago, mp.nombre_metodo
        )
        SELECT
            metodo,
            ROUND(ventas, 2) AS ventas,
            facturas,
            ROUND(
                ventas / NULLIF(SUM(ventas) OVER (), 0) * 100,
                2
            ) AS participacion
        FROM resumen
        ORDER BY ventas DESC
    `;

    const [rows] = await pool.query(sql, parametros);

    return {
        filtros: { anio, sucursal },
        datos: convertirNumeros(rows, [
            'ventas', 'facturas', 'participacion'
        ])
    };
});


// 10. TABLA CRUZADA

const tablaCruzada = ejecutar('tabla-cruzada', async (req) => {
    const anio = obtenerAnio(req.query);

    if (anio === undefined) {
        throw errorValidacion(
            'El parámetro anio es obligatorio.'
        );
    }

    const sucursal = obtenerTexto(req.query, 'sucursal');

    const condiciones = [
        'f.vigente = 1',
        'dt.anio = ?'
    ];

    const parametros = [anio];

    if (sucursal !== undefined) {
        condiciones.push('u.codigo_sucursal = ?');
        parametros.push(sucursal);
    }

    const sql = `
        SELECT
            p.categoria,
            ROUND(SUM(CASE WHEN dt.trimestre = 1
                THEN f.monto_linea ELSE 0 END), 2) AS t1,
            ROUND(SUM(CASE WHEN dt.trimestre = 2
                THEN f.monto_linea ELSE 0 END), 2) AS t2,
            ROUND(SUM(CASE WHEN dt.trimestre = 3
                THEN f.monto_linea ELSE 0 END), 2) AS t3,
            ROUND(SUM(CASE WHEN dt.trimestre = 4
                THEN f.monto_linea ELSE 0 END), 2) AS t4,
            ROUND(SUM(f.monto_linea), 2) AS total
        FROM dw_ventas.fact_ventas f
        INNER JOIN dw_ventas.dim_producto p
            ON f.sk_producto = p.sk_producto
        INNER JOIN dw_ventas.dim_tiempo dt
            ON f.sk_tiempo = dt.sk_tiempo
        INNER JOIN dw_ventas.dim_ubicacion u
            ON f.sk_ubicacion = u.sk_ubicacion
        WHERE ${condiciones.join(' AND ')}
        GROUP BY p.categoria
        ORDER BY p.categoria ASC
    `;

    const [rows] = await pool.query(sql, parametros);

    return {
        filtros: { anio, sucursal },
        datos: convertirNumeros(rows, [
            't1', 't2', 't3', 't4', 'total'
        ])
    };
});


module.exports = {
    indicadores,
    ventasTiempo,
    ventasUbicacion,
    ventasProducto,
    topProductos,
    vendedores,
    clientes,
    comparativo,
    metodosPago,
    tablaCruzada
};
