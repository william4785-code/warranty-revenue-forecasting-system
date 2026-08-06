# Changelog

## Portfolio V2.3 - Application-progress Nowcast and model governance

- Added an open-month h=1 Application-progress Nowcast at validated calendar
  cutoffs 5/10/15/20/25.
- Added prior-month-only progress curves and blend-weight selection.
- Added pooled-curve shrinkage, baseline-only early-month behavior, and a B05
  short-history fallback.
- Added chronological audit helpers and fixed-Challenger promotion gates.
- Recorded Phase 4B as a dynamic-policy promotion candidate.
- Recorded Phase 4B.1 as a failed fixed candidate and retained V2.3.
- Added application-level synthetic data, reproducible demos, and tests.
- Published relative metrics only; no actual revenue or row-level predictions.

## Portfolio V2.2 - 2026-07

### Correctness

- Removed same-month target and operational growth features from XGBoost
  routes.
- Added incomplete-month exclusion.
- Standardized the XGBoost model key to `XGB`.
- Added strict common-key, duplicate-model, missing-prediction, and weight-sum
  checks.
- Replaced independent component-RMSE interval approximation with direct
  Hybrid residual scale.

### Validation

- Added multi-horizon expanding walk-forward backtesting.
- Added Hybrid weights estimated only from prior forecast origins.
- Added RMSE, MAE, MAPE, WAPE, Bias, and sample-count reporting.
- Added explicit short-history fallback behavior.

### Engineering

- Split the monolithic script into reusable R modules.
- Added a fully synthetic end-to-end demo.
- Added `testthat` tests and GitHub Actions validation.
- Added Model Card, validation, data dictionary, feature-availability
  documentation, and a public technical handbook.

## Portfolio V2 - Initial public version

- Added ARIMA, ETS, XGBoost, recursive forecasts, inverse-RMSE Hybrid,
  visualization, MariaDB input, and Excel export.
