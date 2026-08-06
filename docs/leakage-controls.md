# Leakage Controls

## Monthly Forecast Boundary

For every forecast row:

- `max_train_date <= origin`
- `origin < target_date`
- the calendar-month distance from origin to target equals `h`
- incomplete current months are removed before feature engineering
- recursive XGBoost receives prior observations and earlier recursive
  predictions, never future actual values

Feature routes use an allowlist. Same-month outcome growth, contemporaneous
application counts, and other forecast-time unavailable values are blocked.

## Common-Key Comparison

ARIMA, ETS, and XGBoost must provide exactly one prediction for every
branch/origin/target/horizon key. Champion and Challenger comparisons use an
inner join followed by row-count and actual-value reconciliation. Missing or
duplicated keys fail the run.

## Hybrid Weight Boundary

For a backtest row at origin `t`, Hybrid weights may use component errors only
from origins earlier than `t`. Branch/horizon evidence is preferred; branch
evidence and equal-weight cold start are explicit fallbacks.

## Nowcast Boundary

For target month `m`:

- application progress is truncated at the declared cutoff day;
- branch and pooled cumulative-share priors use months before `m`;
- baseline/curve blend weights use months before `m`;
- backtest actuals must reconcile with monthly Hybrid actuals;
- the open month is never added to historical curve or blend training data.

Before day 5, or when evidence is insufficient, the Hybrid h=1 baseline is
preserved.

## Challenger Boundary

Phase 4B used nested expanding origins. Candidate selection happened on inner
origins whose targets were observable by the outer origin. Phase 4B.1 then used
six earlier origins to select one fixed candidate and six later origins for an
untouched test. Parameters and boosting rounds were frozen before test scoring.

Public tests exercise chronology, common-key reconciliation, prior-only blend
selection, and failed promotion gates on synthetic data.
