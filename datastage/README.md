# Diseño Técnico — Parallel Job `jb_ai_economics_etl`

Este directorio documenta la capa de integración ETL en **IBM InfoSphere DataStage** (Parallel Edition) que procesa los logs crudos de telemetría y tablas maestras generadas por la simulación operativa (`generate_data.py`), aplica controles de calidad, calcula métricas económicas y consolida la tabla diaria `ai_economics.ai_usage_daily` en BigQuery junto con el archivo `data/ai_usage_daily.csv`.

## Resumen del job

- **Nombre del job:** `jb_ai_economics_etl`
- **Tipo:** Parallel Job (`JobType = 3`)
- **Granularidad de entrada:** Eventos o micro-lotes de telemetría por gateway/solicitud (`event_timestamp`, `team`, `model`, `environment`, `region`).
- **Granularidad de salida:** Diaria por equipo, modelo y ambiente (`event_date`, `team`, `product`, `provider`, `model`, `environment`, `region`).
- **Volumen consolidado:** **16.200 registros** (180 días desde `2026-02-01` hasta `2026-07-30` × 6 equipos × 5 modelos × 3 ambientes).

### Parámetros del job

| Parámetro | Tipo | Valor por defecto | Descripción |
|---|---|---|---|
| `pInputTelemetryPath` | String | `landing/telemetry_events_raw.csv` | Ruta de logs crudos de telemetría de entrada |
| `pRefModelRatesPath` | String | `ref/model_rates.csv` | Maestro de tarifas por modelo y proveedor |
| `pRefTeamBudgetsPath` | String | `ref/team_budgets.csv` | Maestro de equipos, productos y presupuesto diario |
| `pRejectFilePath` | String | `rejects/ai_telemetry_rejects.csv` | Archivo de rechazos del control de calidad |
| `pBqProjectId` | String | `YOUR_PROJECT_ID` | Proyecto de Google Cloud destino |
| `pBqDataset` | String | `ai_economics` | Dataset en BigQuery |
| `pBqTable` | String | `ai_usage_daily` | Tabla destino particionada y clusterizada |
| `pOutputCsvPath` | String | `data/ai_usage_daily.csv` | Snapshot CSV consolidado para Tableau |

---

## Topología del flujo

```text
  [seq_telemetry_raw] (PxSequentialFile)
           │
           ▼  lnk_raw_telemetry
  [flt_quality_gate] (PxFilter) ──(reject_link)──► [seq_reject_events] (PxSequentialFile)
           │
           ▼  lnk_valid_telemetry
  [lkp_rates_and_budgets] (PxLookup) ◄──(Entire)── [seq_ref_model_rates] (PxSequentialFile)
           │                         ◄──(Entire)── [seq_ref_team_budgets] (PxSequentialFile)
           ▼  lnk_enriched_telemetry
  [xfm_economics_metrics] (PxTransformer)
           │
           ▼  lnk_calculated_metrics
  [agg_daily_usage] (PxAggregator)  [Hash: event_date, team, model, environment]
           │
           ▼  lnk_daily_usage
  [bq_ai_usage_daily] (BigQueryConnectorPX) ──► YOUR_PROJECT_ID.ai_economics.ai_usage_daily
                                            └──► data/ai_usage_daily.csv
```

---

## Detalle por etapa

### a) `Sequential_File` (`PxSequentialFile`)

Lectura paralela de archivos planos delimitados por coma (`,`) con encabezado en la primera fila (`firstLineColumnNames = true`, UTF-8):

1. **`seq_telemetry_raw`** — Logs de telemetría de llamadas a servicios de IA:
   - Columnas leídas: `event_timestamp` (`VarChar(26)`), `team` (`VarChar(64)`), `model` (`VarChar(64)`), `environment` (`VarChar(32)`), `region` (`VarChar(32)`), `requests` (`BigInt`), `input_tokens` (`BigInt`), `output_tokens` (`BigInt`), `avg_latency_ms` (`Integer`), `p95_latency_ms` (`Integer`), `error_count` (`BigInt`), `cache_hit_count` (`BigInt`).
2. **`seq_ref_model_rates`** — Maestro de tarifas y parámetros por modelo:
   - Columnas leídas: `model` (`VarChar(64)`), `provider` (`VarChar(64)`), `input_rate_usd_per_m` (`Decimal(10,4)`), `output_rate_usd_per_m` (`Decimal(10,4)`), `traffic_share` (`Double`), `value_multiplier` (`Double`).
3. **`seq_ref_team_budgets`** — Maestro de equipos, productos y presupuesto diario:
   - Columnas leídas: `team` (`VarChar(64)`), `product` (`VarChar(64)`), `daily_budget_usd` (`Decimal(12,4)`).
4. **`seq_reject_events`** — Archivo destino para filas descartadas desde el `Filter` por el `reject_link` (`rej_invalid_telemetry`).

---

### b) `Filter` (`PxFilter`) — `flt_quality_gate`

Aplica las reglas de integridad estructural y de dominio antes de enriquecer o calcular costos:

- **Condición de paso (`lnk_valid_telemetry`):**
  ```sql
  IsNotNull(event_timestamp)
  AND Trim(team) <> ''
  AND Trim(model) <> ''
  AND environment IN ('production', 'staging', 'development')
  AND requests > 0
  AND input_tokens >= 0
  AND output_tokens >= 0
  AND avg_latency_ms >= 0
  AND p95_latency_ms >= avg_latency_ms
  AND error_count >= 0
  AND error_count <= requests
  AND cache_hit_count >= 0
  AND cache_hit_count <= requests
  ```
- **Manejo de rechazos (`reject_link` -> `seq_reject_events`):**
  - Todo registro que incumpla la condición (claves nulas, ambientes fuera de catálogo, `requests <= 0`, tokens/latencias negativas o conteos inconsistentes) se deriva al `reject_link` con `Output Rejects = True`, permitiendo auditar anomalías de ingesta sin abortar la ejecución.

---

### c) `Lookup` (`PxLookup`) — `lkp_rates_and_budgets`

Enriquece el stream principal `lnk_valid_telemetry` con las dos tablas maestras mediante particionamiento **`Entire`** en ambos enlaces de referencia (adecuado por su baja cardinalidad: 5 modelos y 6 equipos), evitando reparticionamientos de red sobre los logs de telemetría:

- **Enlace primario:** `lnk_valid_telemetry` (particionamiento `Auto`).
- **Referencia 1 (`lnk_ref_models`, particionamiento `Entire`):**
  - Clave de cruce: `lnk_valid_telemetry.model = lnk_ref_models.model`
  - Columnas incorporadas: `provider`, `input_rate_usd_per_m`, `output_rate_usd_per_m`, `traffic_share`, `value_multiplier`.
- **Referencia 2 (`lnk_ref_teams`, particionamiento `Entire`):**
  - Clave de cruce: `lnk_valid_telemetry.team = lnk_ref_teams.team`
  - Columnas incorporadas: `product`, `daily_budget_usd`.
- **Política ante falta de coincidencia (`Lookup Failure`):** `Drop` / `Reject` hacia log operativo para modelos o equipos no dados de alta en los maestros.

---

### d) `Transformer` (`PxTransformer`) — `xfm_economics_metrics`

Normaliza fechas, aplica límites operativos sobre tasas de error/caché y calcula costos, presupuestos prorrateados y valor de negocio mediante **Stage Variables** evaluadas en orden:

| Stage Variable | Tipo | Expresión / Regla de negocio |
|---|---|---|
| `svEventDate` | `Date` | `StringToDate(Left(lnk_enriched_telemetry.event_timestamp, 10), "%yyyy-%mm-%dd")` |
| `svEnvShare` | `Double` | `If lnk_enriched_telemetry.environment = "production" Then 0.86 Else If lnk_enriched_telemetry.environment = "staging" Then 0.10 Else 0.04` |
| `svRawErrorRate` | `Double` | `AsDouble(lnk_enriched_telemetry.error_count) / AsDouble(lnk_enriched_telemetry.requests)` |
| `svErrorRate` | `Double` | `If svRawErrorRate > 0.20 Then 0.20 Else If svRawErrorRate < 0.0 Then 0.0 Else svRawErrorRate` |
| `svSuccessRate` | `Double` | `1.0 - svErrorRate` |
| `svRawCacheHit` | `Double` | `AsDouble(lnk_enriched_telemetry.cache_hit_count) / AsDouble(lnk_enriched_telemetry.requests)` |
| `svCacheHitRate` | `Double` | `If svRawCacheHit > 0.70 Then 0.70 Else If svRawCacheHit < 0.0 Then 0.0 Else svRawCacheHit` |
| `svTokenCost` | `Decimal(18,6)` | `(AsDouble(lnk_enriched_telemetry.input_tokens) / 1000000.0) * lnk_enriched_telemetry.input_rate_usd_per_m + (AsDouble(lnk_enriched_telemetry.output_tokens) / 1000000.0) * lnk_enriched_telemetry.output_rate_usd_per_m` |
| `svInfraMultiplier` | `Double` | `If lnk_enriched_telemetry.provider = "Self-hosted" Then 1.18 Else 1.0` |
| `svCostUsd` | `Decimal(18,4)` | `svTokenCost * svInfraMultiplier * (1.0 - 0.35 * svCacheHitRate)` |
| `svValuePerSuccess` | `Double` | `If lnk_enriched_telemetry.team = "Customer Experience" Then 0.028 Else 0.041` |
| `svBusinessValueUsd` | `Decimal(18,4)` | `AsDouble(lnk_enriched_telemetry.requests) * svSuccessRate * svValuePerSuccess * lnk_enriched_telemetry.value_multiplier` |
| `svAllocatedBudgetUsd` | `Decimal(18,4)` | `lnk_enriched_telemetry.daily_budget_usd * lnk_enriched_telemetry.traffic_share * svEnvShare` |

**Reglas operativas reflejadas:**
- Los modelos `Self-hosted` (`open-70b`) suman un overhead de infraestructura del `+18%` (`svInfraMultiplier = 1.18`).
- El acierto en caché reduce el costo efectivo de tokens hasta en un `35%` (`1 - 0.35 * cache_hit_rate`).
- `embedding-v3` opera con `output_tokens = 0` (`output_rate_usd_per_m = 0.00`) y `value_multiplier = 0.01`.
- Los incidentes simulados los días `7` y `22` de cada mes en `frontier-large` y `reasoning-medium` elevan `error_rate` (`+0.055`, con tope `0.20`) y latencia (`1.55x`), lo que impacta directamente en `svSuccessRate` y `svBusinessValueUsd`.

---

### e) `Aggregator` (`PxAggregator`) — `agg_daily_usage`

Consolida los registros a nivel diario asegurando el ordenamiento y agrupamiento requerido por el esquema analítico:

- **Particionamiento de entrada:** **`Hash`** sobre `(event_date, team, model, environment)`. Garantiza que todos los registros de una misma combinación diaria aterricen en el mismo nodo de procesamiento antes de agrupar.
- **Modo:** `Hash` (en memoria por partición).
- **Claves de agrupación (`GROUP BY`):**
  `event_date`, `team`, `product`, `provider`, `model`, `environment`, `region`
- **Agregaciones por columna:**
  - `requests`: `Sum(requests)` → `INT64`
  - `input_tokens`: `Sum(input_tokens)` → `INT64`
  - `output_tokens`: `Sum(output_tokens)` → `INT64`
  - `avg_latency_ms`: `Mean(avg_latency_ms)` (truncado/redondeado a `INT64`)
  - `p95_latency_ms`: `Max(p95_latency_ms)` → `INT64`
  - `error_rate`: `Mean(error_rate)` → `FLOAT64`
  - `success_rate`: `Mean(success_rate)` → `FLOAT64`
  - `cache_hit_rate`: `Mean(cache_hit_rate)` → `FLOAT64`
  - `cost_usd`: `Sum(cost_usd)` → `NUMERIC`
  - `allocated_budget_usd`: `Max(allocated_budget_usd)` → `NUMERIC` (preserva la asignación diaria sin duplicar por cantidad de lotes intra-día)
  - `business_value_usd`: `Sum(business_value_usd)` → `NUMERIC`
- **Resultado:** `16.200` filas diarias exactas (`180` días × `6` equipos × `5` modelos × `3` ambientes).

---

### f) `BigQuery_Connector` (`BigQueryConnectorPX`) — `bq_ai_usage_daily`

Carga la tabla final en Google BigQuery conforme a `bigquery/schema.sql` y genera el extracto CSV local para el workbook de Tableau:

- **Tabla destino:** `` `YOUR_PROJECT_ID.ai_economics.ai_usage_daily` ``
- **Configuración de tabla BigQuery:**
  - `PARTITION BY event_date`
  - `CLUSTER BY team, model, environment`
  - Ubicación del dataset: `US`
- **Modo de escritura:** `Bulk Load` (via staging GCS / BigQuery Load Job) en modo `Replace` o `Append` idempotente por partición `event_date`.
- **Exportación CSV:** Al finalizar la carga (`After-Job` / `bq extract` sobre la tabla consolidada ordenada por `event_date, team, model, environment`), se genera `data/ai_usage_daily.csv` con las 16.200 filas utilizadas por `tableau/AI-Economics-Dashboard.twb` y las vistas `v_dashboard_daily`, `v_team_monthly` y `v_latest_30d_forecast` de `bigquery/views.sql`.

---

## Catálogo de parámetros de negocio (`generate_data.py`)

### Equipos y presupuestos (`seq_ref_team_budgets`)

| `team` | `product` | `team_scale` | `daily_budget_usd` | `value_per_success` |
|---|---|---:|---:|---:|
| `Risk` | `Fraud Copilot` | 1.35 | 3.60 | 0.041 |
| `Customer Experience` | `Support Assistant` | 1.65 | 5.20 | 0.028 |
| `Marketplace` | `Listing Enrichment` | 1.15 | 3.80 | 0.041 |
| `Fintech` | `Credit Analyst` | 0.95 | 3.50 | 0.041 |
| `Logistics` | `Route Assistant` | 0.75 | 2.80 | 0.041 |
| `Developers` | `Code Assistant` | 1.25 | 3.30 | 0.041 |

### Modelos y tarifas (`seq_ref_model_rates`)

| `model` | `provider` | `input_rate_usd_per_m` | `output_rate_usd_per_m` | `traffic_share` | `value_multiplier` |
|---|---|---:|---:|---:|---:|
| `frontier-large` | `Provider A` | 3.00 | 12.00 | 0.20 | 1.10 |
| `frontier-small` | `Provider A` | 0.35 | 1.40 | 0.37 | 0.75 |
| `reasoning-medium` | `Provider B` | 2.10 | 8.50 | 0.14 | 1.40 |
| `open-70b` | `Self-hosted` | 0.70 | 0.70 | 0.17 | 0.80 |
| `embedding-v3` | `Provider C` | 0.08 | 0.00 | 0.12 | 0.01 |
