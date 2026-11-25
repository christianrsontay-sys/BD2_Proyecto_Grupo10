const express = require('express');

const app = express();

app.use(express.json());

const estadoRoutes = require('./routes/estado.routes');
const reportesRoutes = require('./routes/reportes.routes');

app.use('/api', estadoRoutes);
app.use('/api/reportes', reportesRoutes);

module.exports = app;
