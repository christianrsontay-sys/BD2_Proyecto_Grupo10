const pool = require('../config/database');

const estado = async (req, res) => {
    try {

        const [rows] = await pool.query(`
            SELECT
                DATABASE() AS base_actual,
                NOW() AS fecha_servidor
        `);

        res.json(rows);

    } catch (error) {

        res.status(500).json({
            error: error.message
        });

    }
};

module.exports = {
    estado
};