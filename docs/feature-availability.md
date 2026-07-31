# Feature Availability and Leakage Controls

## Core rule

A feature is allowed only if its value would be known when the forecast is
created.

Historical correlation is not sufficient.

## Leakage taxonomy

| Type | Description | Example | Control |
|---|---|---|---|
| Target leakage | Feature contains the target directly or algebraically | Same-month YoY revenue growth | Blocked feature list |
| Temporal leakage | Future rows affect historical feature calculation | Rolling mean calculated before time split | Calculate from lagged history |
| Availability leakage | Field exists historically but is unknown at forecast time | Future-month claim count | Horizon availability rules |
| Selection leakage | Test period influences feature or parameter choice | Full-history Gain used before backtest | Nested walk-forward |

## Public feature matrix

| Feature family | h=1 | h=2-4 | h=5-6 | Construction |
|---|---:|---:|---:|---|
| Calendar | Yes | Yes | Yes | Future date |
| Target lags 1-3 | Recursive | Recursive | Recursive | Actual history plus earlier predictions |
| Rolling 3/6 revenue | Recursive | Recursive | Recursive | Prior history only |
| Trend and growth | Recursive | Recursive | Recursive | Lag-derived |
| Volatility 3/6 | Recursive | Recursive | Recursive | Lagged windows |
| Lag-12 revenue | Yes | Yes | Yes | Known historical month |
| Same-month target growth | No | No | No | Target leakage |
| Same-month activity counts | No | No | No | Unavailable future value |

## Blocked feature names

The public implementation stops if a route contains:

```text
yoy_growth_revenue
same_month_claim_count
same_month_category_a_count
same_month_category_b_count
```

The list is intentionally explicit so a future code change cannot silently
reintroduce the known leakage pattern.

## Incomplete month

Before feature engineering:

```r
date < floor_date(as_of_date, "month")
```

The open month is excluded because partial revenue would otherwise contaminate
the target, lags, rolling features, and backtests.

## Route governance

Each XGBoost output retains:

- feature-route name;
- feature count;
- forecast horizon;
- branch ID.

These fields explain why two forecasts may use different XGBoost inputs.
