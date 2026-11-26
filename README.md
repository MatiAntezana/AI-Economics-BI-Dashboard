# AI Economics — Cost & ROI Dashboard

Proyecto de Business Intelligence que transforma registros diarios de uso de servicios de IA en indicadores de costo, presupuesto, valor de negocio y retorno de inversión.

Surgió al retomar conceptos vistos en la materia **Base de Datos**, donde conocí el uso de Tableau sobre estructuras SQL. Adapté ese enfoque a un caso de AI Economics y lo convertí en un tablero interactivo, reproducible y público.

> El dataset proviene de una simulación de logs de telemetría y costos operativos de producción. No representa datos reales de Mercado Libre ni de ninguna otra empresa.

<p align="center">
  <a href="https://public.tableau.com/app/profile/matias.antezana/viz/AIEconomicDashboard/AIEconomicsDashboard">
    <img src="https://public.tableau.com/views/AIEconomicDashboard/AIEconomicsDashboard.png?:showVizHome=no" alt="AI Economics Dashboard en Tableau Public" width="100%" />
  </a>
</p>

<p align="center">
  <a href="https://public.tableau.com/app/profile/matias.antezana/viz/AIEconomicDashboard/AIEconomicsDashboard"><strong>Abrir dashboard interactivo en Tableau Public</strong></a>
</p>

## Objetivo

Construir una capa analítica que permita responder preguntas financieras y técnicas sobre infraestructura de IA:

- ¿Cómo evolucionan los costos y el presupuesto asignado?
- ¿Qué equipos concentran el mayor gasto?
- ¿Qué equipos generan más valor en relación con su costo?
- ¿Dónde existen oportunidades de optimización?
- ¿Cómo cambian los resultados entre producción, desarrollo y staging?

## Flujo del proyecto

```text
generate_data.py (fuentes de telemetría y costos operativos de producción)
        ↓
IBM InfoSphere DataStage (jb_ai_economics_etl: calidad, lookup, cálculo y agregación diaria)
        ↓
bigquery/ (schema.sql · views.sql) + data/ai_usage_daily.csv (16.200 registros)
        ↓
Tableau Public
        ↓
Dashboard de costos, valor y ROI
```

El conjunto consolidado contiene **180 días**, **6 equipos**, **5 modelos** y **3 ambientes**. Cada fila representa el uso diario de un modelo por equipo y ambiente.

## Dashboard

El tablero publicado reúne cuatro análisis conectados por un filtro global de ambiente:

1. **Evolución de costos:** compara el costo de infraestructura con el presupuesto asignado a lo largo del tiempo.
2. **Costo por equipo:** ordena los equipos según su gasto total.
3. **Valor vs. costo:** muestra la relación entre inversión y valor de negocio estimado.
4. **ROI por equipo:** compara el retorno relativo mediante un campo calculado en Tableau.

La métrica principal se define como:

```text
ROI = (business value − infrastructure cost) / infrastructure cost
```

## Datos

El generador utiliza una semilla fija (`SEED = 42`) para producir resultados reproducibles. El esquema incluye:

- Dimensiones: fecha, equipo, producto, proveedor, modelo, ambiente y región.
- Volumen: solicitudes, tokens de entrada y tokens de salida.
- Rendimiento: latencia media, latencia P95, tasa de errores y tasa de éxito.
- Economía: costo, presupuesto asignado y valor de negocio estimado.
- Eficiencia: tasa de cache hit y ROI calculado.

Los costos, presupuestos y valores de negocio son parámetros de simulación operativa declarados en `generate_data.py`; por eso los resultados demuestran el método analítico, no el desempeño de una organización real.

## Lectura de los resultados

Para el filtro de **producción**, la simulación de telemetría y costos operativos genera:

| Indicador | Resultado |
|---|---:|
| Solicitudes | 1.977.736 |
| Costo total | USD 3.897,86 |
| Presupuesto asignado | USD 3.436,58 |
| Consumo de presupuesto | 113,4% |
| ROI estimado | 1.473,4% |

Tres observaciones que surgen del tablero:

- **Customer Experience** concentra el mayor costo total: aproximadamente USD 909.
- **Developers** presenta el mayor consumo relativo de presupuesto: aproximadamente 134,8%.
- **Logistics** y **Fintech** permanecen por debajo del presupuesto simulado, mientras que el resto lo supera.

Estos resultados deben interpretarse únicamente dentro del escenario simulado. Su utilidad está en mostrar cómo pasar de registros operativos a métricas comparables y decisiones de gestión.

## ETL en IBM InfoSphere DataStage

La carpeta `datastage/` documenta el diseño del Parallel Job `jb_ai_economics_etl` encargado de transformar los logs crudos de telemetría y maestros de tarifas en la tabla diaria final:

<p align="center">
  <img src="datastage/jb_ai_economics_etl_flow.jpg" alt="Flujo del Parallel Job jb_ai_economics_etl en IBM InfoSphere DataStage" width="100%" />
</p>

- `datastage/README.md`: especificación por etapa (`Sequential_File`, `Filter`, `Lookup` con particionamiento `Entire`, `Transformer` con Stage Variables, `Aggregator` con particionamiento `Hash` y `BigQuery_Connector`).
- `datastage/source_to_target_mapping.csv`: trazabilidad campo a campo hacia las 18 columnas de `ai_economics.ai_usage_daily`.
- `datastage/jb_ai_economics_etl.dsx`: exportación XML del Parallel Job.

## BigQuery

El repositorio incluye una implementación SQL compatible con BigQuery:

- `bigquery/schema.sql`: tabla particionada por fecha y agrupada por equipo, modelo y ambiente.
- `bigquery/views.sql`: vistas para el dashboard, resumen mensual y proyección simple a 30 días.
- `bigquery/analysis_queries.sql`: consultas de presupuesto, economía por modelo y ahorro potencial.

Antes de ejecutarlas, hay que reemplazar `YOUR_PROJECT_ID` por el identificador del proyecto de Google Cloud.

## Reproducir el dataset

Requisito: Python 3.10 o superior. No necesita dependencias externas.

```bash
python3 generate_data.py
```

El comando vuelve a crear `data/ai_usage_daily.csv` con 16.200 filas.

Para explorar el workbook localmente:

1. Instalar Tableau Desktop Public Edition.
2. Abrir `tableau/AI-Economics-BI-Dashboard.twbx`.
3. Si Tableau solicita actualizar la fuente, seleccionar `data/ai_usage_daily.csv`.

El archivo `tableau/AI-Economics-Dashboard.twb` contiene la versión final del workbook publicada en Tableau Public.

## Estructura

```text
AI-Economics-BI-Dashboard/
├── bigquery/
│   ├── analysis_queries.sql
│   ├── schema.sql
│   └── views.sql
├── data/
│   └── ai_usage_daily.csv
├── datastage/
│   ├── README.md
│   ├── jb_ai_economics_etl.dsx
│   ├── jb_ai_economics_etl_flow.jpg
│   └── source_to_target_mapping.csv
├── tableau/
│   ├── AI-Economics-BI-Dashboard.twbx
│   ├── AI-Economics-Dashboard.twb
│   └── BUILD_GUIDE.md
├── generate_data.py
├── LICENSE
└── README.md
```

## Qué demuestra

- Experiencia práctica construyendo un dashboard end-to-end en Tableau.
- Diseño de métricas orientadas a decisiones de negocio.
- Integración ETL en IBM InfoSphere DataStage con trazabilidad source-to-target.
- Modelado analítico y consultas SQL para BigQuery.
- Simulación reproducible de logs de telemetría y costos operativos con Python.
- Comunicación clara de supuestos, resultados y limitaciones.

## Limitaciones y próximas mejoras

- Los registros y valores económicos provienen de una simulación de telemetría y costos operativos de producción.
- Las consultas de BigQuery están preparadas, pero el dashboard público utiliza un extracto del CSV para evitar requisitos de licencia.
- El ROI representa valor estimado, no ingresos observados.
- Una siguiente versión podría automatizar cargas, agregar alertas presupuestarias y comparar la proyección simple con un modelo temporal.

## Licencia

MIT. Consultar [LICENSE](LICENSE).
