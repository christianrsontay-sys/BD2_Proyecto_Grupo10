const indicadores = async (req, res) => {
    res.json({
        reporte: "indicadores",
        filtros: req.query,
        datos: []
    });
};

const ventasTiempo = async (req, res) => {
    res.json({
        reporte: "ventas-tiempo",
        filtros: req.query,
        datos: []
    });
};

const ventasUbicacion = async (req, res) => {
    res.json({
        reporte: "ventas-ubicacion",
        filtros: req.query,
        datos: []
    });
};

const ventasProducto = async (req, res) => {
    res.json({
        reporte: "ventas-producto",
        filtros: req.query,
        datos: []
    });
};

const topProductos = async (req, res) => {
    res.json({
        reporte: "top-productos",
        filtros: req.query,
        datos: []
    });
};

const vendedores = async (req, res) => {
    res.json({
        reporte: "vendedores",
        filtros: req.query,
        datos: []
    });
};

const clientes = async (req, res) => {
    res.json({
        reporte: "clientes",
        filtros: req.query,
        datos: []
    });
};

const comparativo = async (req, res) => {
    res.json({
        reporte: "comparativo",
        filtros: req.query,
        datos: []
    });
};

const metodosPago = async (req, res) => {
    res.json({
        reporte: "metodos-pago",
        filtros: req.query,
        datos: []
    });
};

const tablaCruzada = async (req, res) => {
    res.json({
        reporte: "tabla-cruzada",
        filtros: req.query,
        datos: []
    });
};

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
