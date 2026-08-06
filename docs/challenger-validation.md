# Phase 4B / 4B.1 Challenger Validation

## Question

Can leakage-safe XGBoost tuning improve the production forecasting system after
the downstream Hybrid and application-progress Nowcast are rebuilt under the
same time constraints?

## Phase 4B: Dynamic Nested Reselection

Each outer forecast origin selected one shared parameter row using earlier
inner origins. Features and branch routes remained frozen. ARIMA and ETS stayed
fixed, while Hybrid weights and Nowcast estimates were rebuilt using prior-only
history.

Sanitized aggregate results:

| Gate | Result |
|---|---:|
| XGBoost RMSE change | -2.69% |
| XGBoost change without stress month | -8.97% |
| Hybrid RMSE change | -0.35% |
| Improved horizons | 4/6 |
| Improved Nowcast cutoffs | 5/5 |
| Materially degraded established branches | 0 |
| Short-history fallback | Unchanged |

All programmed gates passed, but 12 outer folds selected seven different
candidates. The all-history candidate was not selected by any outer fold. The
result therefore supported a dynamic reselection policy, not a fixed deployment
row.

## Phase 4B.1: Fixed Chronological Holdout

Six earlier origins selected one candidate and its boosting rounds. The row was
frozen before evaluation on six later origins.

| Gate | Result |
|---|---:|
| XGBoost RMSE change | +9.60% |
| XGBoost change without stress month | +4.58% |
| Hybrid RMSE change | +3.64% |
| Improved horizons | 2/6 |
| Improved Nowcast cutoffs | 0/5 |
| Improved cutoffs without stress month | 1/5 |
| Materially degraded established branches | 2 |
| Short-history fallback | Unchanged |

The fixed Challenger failed XGBoost, horizon-breadth, Hybrid, Nowcast, and
branch guardrail gates. The decision was `RETAIN_V2_3`.

## QA Evidence

- Dynamic experiment: 456 chronology-audit rows, zero failures
- Fixed holdout: five chronology checks, zero failures
- Dynamic control reconstruction: 228/228 common keys exact
- Fixed-holdout control reconstruction: 84/84 common keys exact
- Stress-month exclusion produced the same fixed-Challenger retain decision

## Interpretation

This is a negative deployment result, not a failed research exercise. It shows
that adaptive model-selection gains did not transfer to the tested static
parameter row. The six-origin test is sufficient to reject this promotion, but
not to claim that no future Challenger can work.

Only relative changes and gate outcomes are public. Exact revenue, predictions,
branch-level rankings, dates tied to business events, snapshots, and model
artifacts remain private.
