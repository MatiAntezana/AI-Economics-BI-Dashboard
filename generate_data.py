"""Generate a reproducible synthetic dataset for the AI Economics BI project.

The data is intentionally synthetic: it represents the usage and economics of
LLM services across product teams without exposing real company information.
"""

from __future__ import annotations

import csv
import math
import random
from datetime import date, timedelta
from pathlib import Path


SEED = 42
DAYS = 180
END_DATE = date(2026, 7, 30)
OUTPUT = Path(__file__).parent / "data" / "ai_usage_daily.csv"

TEAMS = {
    "Risk": ("Fraud Copilot", 1.35, 3.60),
    "Customer Experience": ("Support Assistant", 1.65, 5.20),
    "Marketplace": ("Listing Enrichment", 1.15, 3.80),
    "Fintech": ("Credit Analyst", 0.95, 3.50),
    "Logistics": ("Route Assistant", 0.75, 2.80),
    "Developers": ("Code Assistant", 1.25, 3.30),
}

MODELS = {
    # provider, input USD/M tokens, output USD/M tokens, base latency ms,
    # relative traffic share
    "frontier-large": ("Provider A", 3.00, 12.00, 1450, 0.20),
    "frontier-small": ("Provider A", 0.35, 1.40, 620, 0.37),
    "reasoning-medium": ("Provider B", 2.10, 8.50, 2100, 0.14),
    "open-70b": ("Self-hosted", 0.70, 0.70, 980, 0.17),
    "embedding-v3": ("Provider C", 0.08, 0.00, 180, 0.12),
}

VALUE_MULTIPLIER = {
    "frontier-large": 1.10,
    "frontier-small": 0.75,
    "reasoning-medium": 1.40,
    "open-70b": 0.80,
    "embedding-v3": 0.01,
}


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(value, high))


def main() -> None:
    rng = random.Random(SEED)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    start = END_DATE - timedelta(days=DAYS - 1)

    columns = [
        "event_date",
        "team",
        "product",
        "provider",
        "model",
        "environment",
        "region",
        "requests",
        "input_tokens",
        "output_tokens",
        "avg_latency_ms",
        "p95_latency_ms",
        "error_rate",
        "success_rate",
        "cache_hit_rate",
        "cost_usd",
        "allocated_budget_usd",
        "business_value_usd",
    ]

    with OUTPUT.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()

        for day_index in range(DAYS):
            current = start + timedelta(days=day_index)
            growth = 1 + 0.65 * day_index / (DAYS - 1)
            weekday_factor = 0.56 if current.weekday() >= 5 else 1.0
            seasonal = 1 + 0.09 * math.sin(day_index / 13)

            for team, (product, team_scale, daily_budget) in TEAMS.items():
                for model, model_info in MODELS.items():
                    provider, in_rate, out_rate, base_latency, share = model_info
                    for environment, env_share in (("production", 0.86), ("staging", 0.10), ("development", 0.04)):
                        base_requests = 1550 * team_scale * share * env_share
                        requests = max(
                            1,
                            round(base_requests * growth * weekday_factor * seasonal * rng.uniform(0.88, 1.12)),
                        )

                        is_embedding = model == "embedding-v3"
                        avg_input = rng.uniform(520, 1150) if not is_embedding else rng.uniform(280, 620)
                        avg_output = 0 if is_embedding else rng.uniform(140, 460)
                        input_tokens = round(requests * avg_input)
                        output_tokens = round(requests * avg_output)

                        incident = current.day in (7, 22) and model in ("frontier-large", "reasoning-medium")
                        error_rate = rng.uniform(0.006, 0.024) + (0.055 if incident else 0)
                        error_rate = clamp(error_rate, 0, 0.20)
                        latency_factor = 1.55 if incident else 1.0
                        avg_latency = round(base_latency * latency_factor * rng.uniform(0.86, 1.14))
                        p95_latency = round(avg_latency * rng.uniform(1.55, 2.05))
                        cache_hit = clamp(rng.uniform(0.08, 0.44) + day_index * 0.0009, 0, 0.70)

                        token_cost = input_tokens / 1_000_000 * in_rate + output_tokens / 1_000_000 * out_rate
                        infra_multiplier = 1.18 if provider == "Self-hosted" else 1.0
                        cost = token_cost * infra_multiplier * (1 - 0.35 * cache_hit)
                        success_rate = 1 - error_rate
                        value_per_success = 0.028 if team == "Customer Experience" else 0.041
                        business_value = (
                            requests * success_rate * value_per_success * VALUE_MULTIPLIER[model]
                        )
                        allocated_budget = daily_budget * share * env_share

                        writer.writerow(
                            {
                                "event_date": current.isoformat(),
                                "team": team,
                                "product": product,
                                "provider": provider,
                                "model": model,
                                "environment": environment,
                                "region": "southamerica-east1",
                                "requests": requests,
                                "input_tokens": input_tokens,
                                "output_tokens": output_tokens,
                                "avg_latency_ms": avg_latency,
                                "p95_latency_ms": p95_latency,
                                "error_rate": f"{error_rate:.6f}",
                                "success_rate": f"{success_rate:.6f}",
                                "cache_hit_rate": f"{cache_hit:.6f}",
                                "cost_usd": f"{cost:.4f}",
                                "allocated_budget_usd": f"{allocated_budget:.4f}",
                                "business_value_usd": f"{business_value:.4f}",
                            }
                        )

    print(f"Generated {DAYS * len(TEAMS) * len(MODELS) * 3:,} rows at {OUTPUT}")


if __name__ == "__main__":
    main()
