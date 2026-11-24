
const pool = require('../config/database');

const vendedores = async (req, res) => {
    try {
        const [rows] = await pool.query(`
            SELECT
                v.codigo_vendedor,
                v.nombre_completo,
                v.codigo_sucursal,
                v.nombre_sucursal,
                COUNT(DISTINCT f.numero_factura) AS total_facturas,
                SUM(f.cantidad) AS unidades_vendidas,
                SUM(f.monto_linea) AS monto_total
            FROM dw_ventas.dim_vendedor v
            LEFT JOIN dw_ventas.fact_ventas f
                ON v.sk_vendedor = f.sk_vendedor
            GROUP BY
                v.sk_vendedor,
                v.codigo_vendedor,
                v.nombre_completo,
                v.codigo_sucursal,
                v.nombre_sucursal
            ORDER BY monto_total DESC
        `);

        res.json({
            reporte: 'vendedores',
            filtros: req.query,
            datos: rows
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};

const metodosPago = async (req, res) => {
    try {
        const [rows] = await pool.query(`
            SELECT
                mp.nombre_metodo,
                COUNT(DISTINCT f.numero_factura) AS total_facturas,
                SUM(f.cantidad) AS unidades_vendidas,
                SUM(f.monto_linea) AS monto_total
            FROM dw_ventas.dim_metodo_pago mp
            LEFT JOIN dw_ventas.fact_ventas f
                ON mp.sk_metodo_pago = f.sk_metodo_pago
            GROUP BY
                mp.sk_metodo_pago,
                mp.nombre_metodo
            ORDER BY monto_total DESC
        `);

        res.json({
            reporte: 'metodos-pago',
            filtros: req.query,
            datos: rows
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};

module.exports = {
    vendedores,
    metodosPago
};
