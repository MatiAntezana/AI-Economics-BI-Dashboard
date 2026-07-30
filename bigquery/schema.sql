-- Replace YOUR_PROJECT_ID before running this script in BigQuery.
CREATE SCHEMA IF NOT EXISTS `YOUR_PROJECT_ID.ai_economics`
OPTIONS(location = "US");

CREATE OR REPLACE TABLE `YOUR_PROJECT_ID.ai_economics.ai_usage_daily` (
  event_date DATE,
  team STRING,
  product STRING,
  provider STRING,
  model STRING,
  environment STRING,
  region STRING,
  requests INT64,
  input_tokens INT64,
  output_tokens INT64,
  avg_latency_ms INT64,
  p95_latency_ms INT64,
  error_rate FLOAT64,
  success_rate FLOAT64,
  cache_hit_rate FLOAT64,
  cost_usd NUMERIC,
  allocated_budget_usd NUMERIC,
  business_value_usd NUMERIC
)
PARTITION BY event_date
CLUSTER BY team, model, environment;
