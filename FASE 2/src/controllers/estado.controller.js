const pool = require('../config/database');

const estado = async (req, res) => {

    try {

        const [rows] = await pool.query(`
            SELECT
                MAX(fecha_fin) AS ultima_carga
            FROM dw_control
        `);

        res.json({
            ultima_carga: rows[0].ultima_carga,
            estado: 'PENDIENTE',
            filas_hechos: 0
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