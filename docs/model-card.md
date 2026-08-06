# Model Card: Warranty Revenue Forecasting System V2.3

## Status

- Monthly Champion: Portfolio V2.3 Hybrid
- Intramonth layer: Application-progress Nowcast for open-month `h = 1`
- Dynamic XGBoost retuning: experimental policy only
- Fixed XGBoost Challenger: rejected
- Promotion decision: `RETAIN_V2_3`

## Intended Use

The system supports planning and analyst review by forecasting six monthly
horizons for multiple operating units. During an open month it can update the
first horizon using cumulative application activity observed through validated
calendar-day cutoffs.

It is not an accounting ledger, automated revenue commitment, or substitute for
operational judgment.

## Inputs

Monthly layer:

- `date`
- `branch_id`
- `revenue`

Optional application-progress layer:

- `application_id`
- `branch_id`
- `application_date`
- `amount`

All public examples are synthetic. Public branch IDs have no mapping to real
locations.

## Model Components

- ARIMA for linear autocorrelation and differencing
- ETS for level, trend, and seasonality
- Recursive XGBoost for nonlinear lag and calendar effects
- Hybrid using inverse walk-forward RMSE weights
- Application-progress Nowcast using historical cumulative-share curves

## Validation

- Expanding multi-horizon walk-forward forecasts
- Identical Champion/Challenger evaluation keys
- Training cutoff not later than forecast origin
- Hybrid weights calculated from earlier origins only
- Nowcast curves and blend weights calculated from prior completed months only
- Current incomplete month excluded from monthly training
- Branch degradation guardrail
- Stress-month sensitivity analysis
- Frozen-candidate chronological holdout

## Fallbacks

- Before the first validated cutoff, retain the Hybrid baseline.
- If application history is insufficient, set the curve weight to zero.
- If a branch lacks adequate h=1 backtest evidence, retain the baseline.
- Public branch B05 always demonstrates the short-history fallback.
- If branch-level interval evidence is sparse, use pooled cutoff error; otherwise
  retain the baseline interval.

## Challenger Decision

Dynamic nested tuning improved aggregate XGBoost performance by 2.69%, but the
effect belonged to a policy that repeatedly selected parameters. A frozen
candidate chosen on six development origins worsened XGBoost RMSE by 9.60% and
Hybrid RMSE by 3.64% on six later origins. It failed horizon breadth, Nowcast,
and branch guardrail gates. V2.3 was retained.

The negative result is part of the model record. It must not be omitted from a
deployment or portfolio summary.

## Known Limitations

- Monthly samples are small relative to the XGBoost parameter space.
- Recursive forecasts can accumulate error at longer horizons.
- Structural shifts may invalidate progress curves and model weights.
- Application timing can change independently of final monthly revenue.
- Residual intervals are empirical approximations rather than fully calibrated
  probabilistic forecasts.
- The fixed holdout contained six origins, sufficient to reject this promotion
  but not to establish a universal conclusion about all parameter sets.

## Monitoring

Track RMSE, MAE, WAPE, Bias, interval coverage, fallback frequency, curve
weight, progress-curve drift, missing keys, branch concentration, and material
degradation relative to the Champion.

## Governance

Promotion requires improvements at the XGBoost, Hybrid, and Nowcast layers,
broad horizon support, no material branch degradation, stress-period
sensitivity, and an unchanged short-history fallback. A failed downstream gate
retains the current Champion even when an upstream metric improves.
