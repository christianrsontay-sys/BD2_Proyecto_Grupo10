
const express = require('express');

const router = express.Router();

const {
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
} = require('../controllers/reportes.controller');

router.get('/indicadores', indicadores);
router.get('/ventas-tiempo', ventasTiempo);
router.get('/ventas-ubicacion', ventasUbicacion);
router.get('/ventas-producto', ventasProducto);
router.get('/top-productos', topProductos);
router.get('/vendedores', vendedores);
router.get('/clientes', clientes);
router.get('/comparativo', comparativo);
router.get('/metodos-pago', metodosPago);
router.get('/tabla-cruzada', tablaCruzada);

module.exports = router;
