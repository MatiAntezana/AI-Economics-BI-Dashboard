-- Replace YOUR_PROJECT_ID before running this script in BigQuery.

CREATE OR REPLACE VIEW `YOUR_PROJECT_ID.ai_economics.v_dashboard_daily` AS
SELECT
  event_date,
  team,
  product,
  provider,
  model,
  environment,
  region,
  SUM(requests) AS requests,
  SUM(input_tokens + output_tokens) AS total_tokens,
  SUM(cost_usd) AS cost_usd,
  SUM(allocated_budget_usd) AS allocated_budget_usd,
  SUM(business_value_usd) AS business_value_usd,
  SAFE_DIVIDE(SUM(cost_usd), SUM(requests)) * 1000 AS cost_per_1k_requests,
  SAFE_DIVIDE(SUM(business_value_usd) - SUM(cost_usd), SUM(cost_usd)) AS roi,
  SAFE_DIVIDE(SUM(requests * success_rate), SUM(requests)) AS success_rate,
  SAFE_DIVIDE(SUM(requests * error_rate), SUM(requests)) AS error_rate,
  SAFE_DIVIDE(SUM(requests * cache_hit_rate), SUM(requests)) AS cache_hit_rate,
  SAFE_DIVIDE(SUM(requests * avg_latency_ms), SUM(requests)) AS avg_latency_ms,
  SAFE_DIVIDE(SUM(requests * p95_latency_ms), SUM(requests)) AS p95_latency_ms
FROM `YOUR_PROJECT_ID.ai_economics.ai_usage_daily`
GROUP BY 1, 2, 3, 4, 5, 6, 7;

CREATE OR REPLACE VIEW `YOUR_PROJECT_ID.ai_economics.v_team_monthly` AS
SELECT
  DATE_TRUNC(event_date, MONTH) AS month,
  team,
  SUM(requests) AS requests,
  SUM(cost_usd) AS cost_usd,
  SUM(allocated_budget_usd) AS budget_usd,
  SUM(business_value_usd) AS business_value_usd,
  SUM(cost_usd) - SUM(allocated_budget_usd) AS budget_variance_usd,
  SAFE_DIVIDE(SUM(cost_usd), SUM(allocated_budget_usd)) AS budget_consumption,
  SAFE_DIVIDE(SUM(business_value_usd) - SUM(cost_usd), SUM(cost_usd)) AS roi
FROM `YOUR_PROJECT_ID.ai_economics.ai_usage_daily`
WHERE environment = "production"
GROUP BY 1, 2;

CREATE OR REPLACE VIEW `YOUR_PROJECT_ID.ai_economics.v_latest_30d_forecast` AS
WITH bounds AS (
  SELECT MAX(event_date) AS max_date
  FROM `YOUR_PROJECT_ID.ai_economics.ai_usage_daily`
),
recent AS (
  SELECT
    team,
    SUM(cost_usd) AS cost_30d,
    COUNT(DISTINCT event_date) AS observed_days
  FROM `YOUR_PROJECT_ID.ai_economics.ai_usage_daily`, bounds
  WHERE environment = "production"
    AND event_date BETWEEN DATE_SUB(max_date, INTERVAL 29 DAY) AND max_date
  GROUP BY team
)
SELECT
  team,
  cost_30d,
  SAFE_DIVIDE(cost_30d, observed_days) * 30 AS projected_next_30d_cost
FROM recent;
