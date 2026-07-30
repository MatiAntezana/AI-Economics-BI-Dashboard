-- Interview-ready analyses. Replace YOUR_PROJECT_ID before running.

-- 1) Which teams exceed their production budget?
SELECT
  team,
  ROUND(SUM(cost_usd), 2) AS cost_usd,
  ROUND(SUM(allocated_budget_usd), 2) AS budget_usd,
  ROUND(SUM(cost_usd) - SUM(allocated_budget_usd), 2) AS variance_usd
FROM `YOUR_PROJECT_ID.ai_economics.ai_usage_daily`
WHERE environment = "production"
GROUP BY team
ORDER BY variance_usd DESC;

-- 2) Models with poor unit economics or reliability.
SELECT
  model,
  ROUND(SAFE_DIVIDE(SUM(cost_usd), SUM(requests)) * 1000, 3) AS cost_per_1k_requests,
  ROUND(SAFE_DIVIDE(SUM(requests * error_rate), SUM(requests)) * 100, 2) AS error_pct,
  ROUND(SAFE_DIVIDE(SUM(requests * p95_latency_ms), SUM(requests)), 0) AS p95_latency_ms,
  ROUND(SAFE_DIVIDE(SUM(business_value_usd) - SUM(cost_usd), SUM(cost_usd)), 2) AS roi
FROM `YOUR_PROJECT_ID.ai_economics.ai_usage_daily`
WHERE environment = "production"
GROUP BY model
ORDER BY cost_per_1k_requests DESC;

-- 3) Potential savings if traffic from the most expensive model is shifted.
WITH model_cost AS (
  SELECT
    model,
    SUM(requests) AS requests,
    SAFE_DIVIDE(SUM(cost_usd), SUM(requests)) AS cost_per_request
  FROM `YOUR_PROJECT_ID.ai_economics.ai_usage_daily`
  WHERE environment = "production"
  GROUP BY model
), ranked AS (
  SELECT *, ROW_NUMBER() OVER (ORDER BY cost_per_request DESC) AS expensive_rank
  FROM model_cost
)
SELECT
  expensive.model AS source_model,
  cheaper.model AS target_model,
  ROUND(expensive.requests * 0.20 * (expensive.cost_per_request - cheaper.cost_per_request), 2)
    AS estimated_savings_for_20pct_shift_usd
FROM ranked AS expensive
CROSS JOIN ranked AS cheaper
WHERE expensive.expensive_rank = 1
  AND cheaper.expensive_rank = 2;
