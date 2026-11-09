// Valores compartidos por los modelos. Se usan como ${constants.RUN_DATE} en los .sqlx.
const RUN_DATE = dataform.projectConfig.vars.run_date;

// Fechas "abiertas" de una dimensión SCD2.
const SCD_OPEN_FROM = "1900-01-01"; // primera versión conocida: no sabemos qué había antes
const SCD_OPEN_TO = "9999-12-31";   // versión vigente

// Clave del miembro desconocido: los hechos nunca quedan con FK nula.
const UNKNOWN_SK = -1;

module.exports = { RUN_DATE, SCD_OPEN_FROM, SCD_OPEN_TO, UNKNOWN_SK };
