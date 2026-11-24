
const pool = require('../config/database');

const estado = async (req, res) => {
    try {
        const [rows] = await pool.query(`
            SELECT
                fecha_fin AS ultima_carga,
                estado
            FROM dw_control
            ORDER BY id_control DESC
            LIMIT 1
        `);

        const [ventas] = await pool.query(`
            SELECT COUNT(*) AS filas_hechos
            FROM fact_ventas
        `);

        res.json({
            ultima_carga: rows[0]?.ultima_carga || null,
            estado: rows[0]?.estado || 'PENDIENTE',
            filas_hechos: ventas[0].filas_hechos
        });

    } catch (error) {
        res.status(500).json({
            error: error.message
        });
    }
};

module.exports = {
    estado
};
