# Changelog

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
