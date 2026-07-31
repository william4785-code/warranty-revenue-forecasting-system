# Model Card: Warranty Revenue Forecasting System Portfolio V2.2

## Model overview

Portfolio V2.2 forecasts monthly warranty revenue by anonymized service branch
for horizons one through six. It combines three component models:

- ARIMA;
- ETS;
- recursive XGBoost.

An adaptive Hybrid combines component forecasts using inverse-RMSE weights.
During backtesting, weights for a forecast origin are estimated only from
earlier origins.

## Intended use

- monthly planning and target-risk discussion;
- branch-level forecast comparison;
- model research and governance demonstration;
- scenario support when combined with business judgment.

## Out-of-scope use

- accounting recognition or audited financial reporting;
- claim-level approval or customer decisions;
- automatic staffing or budget commitments without review;
- use on daily data without redesigning the validation framework;
- use in a new business domain without re-estimation.

## Inputs

Required public schema:

| Field | Type | Meaning |
|---|---|---|
| `date` | Date | First day of a completed calendar month |
| `branch_id` | Character | Anonymized branch identifier |
| `revenue` | Numeric | Monthly target variable |

Optional activity fields in the synthetic generator are not currently included
in the production feature routes.

## Features

The public model uses only forecast-time-valid fields:

- calendar month, quarter, and year;
- lagged revenue at 1, 2, 3, 6, and 12 months;
- rolling means using prior months only;
- lag-derived trend and growth;
- rolling volatility using prior months only;
- sine and cosine month encodings.

Same-month target growth and future activity counts are blocked.

## Training and validation

- expanding walk-forward evaluation;
- horizons `h = 1,...,6`;
- common branch-origin-date-horizon keys across all component models;
- prior-origin Hybrid weights;
- residual-based Hybrid interval scale;
- explicit short-history fallback.

## Metrics

Primary:

- RMSE.

Supporting:

- MAE;
- MAPE;
- WAPE;
- Bias;
- sample count.

Metrics are never compared across models unless the models share the same
evaluation keys.

## Known limitations

- Revenue may contain large, irregular cases that cannot be inferred from
  historical totals.
- MAPE is unstable when actual revenue is near zero.
- Recursive XGBoost compounds its own uncertainty at longer horizons.
- Inverse-RMSE weighting does not guarantee the optimal portfolio.
- A 95% residual interval is not automatically a calibrated 95% probability
  statement.
- Synthetic demo accuracy cannot be interpreted as business performance.

## Fallback behavior

The public policy demonstrates:

- conservative core features for a guardrail branch;
- a reduced minimum complete-row threshold for a short-history branch;
- branch-level weight fallback when branch-horizon evidence is insufficient;
- equal-weight cold start when no prior error history exists.

Fallback sources are retained in outputs for auditability.

## Human oversight

Users should review:

- unusual revenue spikes;
- data completion status;
- interval width;
- bias and drift;
- changes in the best model by branch and horizon;
- whether operational or policy changes invalidate historical relationships.

## Privacy

All repository examples use synthetic B01-B05 identifiers. No mapping to real
branches or company records exists in the public project.
