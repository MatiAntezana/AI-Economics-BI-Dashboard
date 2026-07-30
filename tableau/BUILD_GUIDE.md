# Guía de construcción en Tableau Public

Esta guía documenta la versión publicada del dashboard. La fuente utilizada es `data/ai_usage_daily.csv`, con 16.200 registros sintéticos.

## 1. Conectar los datos

1. Abrir Tableau Desktop Public Edition.
2. Elegir **Text file** y seleccionar `data/ai_usage_daily.csv`.
3. Confirmar los tipos: `event_date` como fecha; costos y tasas como números; solicitudes y tokens como enteros.
4. Seleccionar **Extract**, requisito para publicar en Tableau Public.

## 2. Campo calculado

### ROI

```tableau
(SUM([Business Value Usd]) - SUM([Cost Usd])) / SUM([Cost Usd])
```

Aplicar formato de porcentaje con un decimal.

## 3. Hojas

### Evolución de costos

- Columns: `Event Date` continuo.
- Rows: `SUM(Cost Usd)` y `SUM(Allocated Budget Usd)`.
- Marks: línea.
- Objetivo: comparar gasto y presupuesto a lo largo del tiempo.

### Costo por equipo

- Rows: `Team`.
- Columns: `SUM(Cost Usd)`.
- Marks: barras.
- Orden: costo descendente.

### Valor vs costo

- Columns: `SUM(Cost Usd)`.
- Rows: `SUM(Business Value Usd)`.
- Detail, Color y Label: `Team`.
- Marks: círculos.

### ROI por equipo

- Rows: `Team`.
- Columns: `ROI`.
- Marks: barras.
- Orden: ROI descendente.

## 4. Dashboard

Crear `AI Economics Dashboard` con las cuatro hojas en una cuadrícula 2 × 2:

```text
Evolución de costos | Valor vs costo
Costo por equipo    | ROI por equipo
```

Agregar `Environment` como filtro global y aplicarlo a todas las hojas que utilizan la fuente. La versión publicada comienza con `production` seleccionado.

## 5. Validaciones

1. Cambiar el ambiente y confirmar que las cuatro visualizaciones respondan.
2. Comparar el costo por equipo con `bigquery/analysis_queries.sql`.
3. Confirmar que ROI se muestre como porcentaje.
4. Abrir el enlace público en una ventana privada.
5. Mantener visible la aclaración de que los datos son sintéticos en la documentación del proyecto.
