# Validation Methodology

## Objective

Estimate how each model would have performed if it had been run at historical
forecast origins with access only to information available at that time.

## Expanding walk-forward design

For each branch:

1. Select a historical forecast origin.
2. Train with months at or before that origin.
3. Predict horizons one through six.
4. Store `origin`, `date`, `branch_id`, `h`, `model`, `actual`, and `pred`.
5. Advance the origin and repeat.

Unlike random cross-validation, this preserves time order.

## Common-key evaluation

Every valid branch-origin-date-horizon key must contain exactly:

- one ARIMA prediction;
- one ETS prediction;
- one XGB prediction;
- one unique actual value.

The pipeline stops on:

- missing models;
- duplicate models;
- missing predictions;
- inconsistent actual values.

This prevents one model from appearing superior merely because it was
evaluated on easier months.

## Multi-horizon interpretation

| Horizon | Interpretation | Main concern |
|---|---|---|
| h=1 | Next month | Most recent lags are available |
| h=2-4 | Short to medium term | Recursive values begin to enter features |
| h=5-6 | Longer term | Fewer external signals would be forecast-time valid |

The XGBoost feature router therefore changes by horizon.

## Independent Hybrid backtest weights

For an evaluation origin `t`, Hybrid weights are estimated from origins
strictly earlier than `t`.

Priority:

1. prior errors for the same branch and horizon, when sufficiently populated;
2. prior errors for the same branch;
3. equal weights for cold start.

This avoids evaluating weights on the same residuals used to create them.

## Error metrics

Let `e = prediction - actual`.

| Metric | Definition | Use |
|---|---|---|
| RMSE | `sqrt(mean(e^2))` | Primary ranking; penalizes large misses |
| MAE | `mean(abs(e))` | Typical absolute error |
| MAPE | `mean(abs(e / actual)) * 100` | Relative error; unstable near zero |
| WAPE | `sum(abs(e)) / sum(abs(actual)) * 100` | Volume-weighted relative error |
| Bias | `mean(e)` | Positive means over-forecasting |
| n | Valid prediction count | Evidence strength |

## Hybrid intervals

The system reconstructs historical Hybrid predictions and calculates Hybrid
RMSE directly from their residuals.

This retains correlation among component-model errors. The interval is:

```text
lower95 = max(0, prediction - 1.96 * Hybrid RMSE)
upper95 = prediction + 1.96 * Hybrid RMSE
```

Branch-horizon residual scale is preferred. Branch-level residual scale is the
fallback when a horizon has fewer than three observations.

## Feature and parameter experiments

Feature selection and hyperparameter tuning must be nested:

- outer loop: untouched forecast origin;
- inner loop: feature selection or parameter choice using earlier data only.

The same final period must not be repeatedly used for design decisions and
then described as unseen test data.

Recommended evidence:

- point RMSE change;
- bootstrap confidence interval;
- probability of beating the baseline;
- branch-level deterioration guardrail;
- performance by horizon.

## Remaining robustness work

- empirical 80% and 95% interval coverage;
- model and feature drift monitoring;
- nested feature and hyperparameter selection;
- operational-pipeline nowcasting;
- longer short-history branch evaluation.
