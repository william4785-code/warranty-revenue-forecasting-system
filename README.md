# Warranty Revenue Forecasting System

An end-to-end R forecasting project for predicting monthly warranty claim
revenue across multiple service branches and supporting revenue target
management.

> This repository contains a sanitized portfolio version. Company data,
> credentials, internal database names, branch identifiers, and generated
> reports are not included.

## Companion Analytics Engineering Layer

This forecasting repository is paired with
[warranty-analytics-engineering-layer](https://github.com/william4785-code/warranty-analytics-engineering-layer),
a synthetic-only dbt Core + DuckDB project that demonstrates the governed data
layer around warranty forecasting.

```text
dbt + DuckDB analytics engineering layer
  sources -> tested grains -> point-in-time features -> prediction contract
                                                        |
                                                        v
R forecasting system
  model fitting -> walk-forward validation -> forecasts -> promotion decisions
                                                        |
                                                        v
dbt monitoring
  common-key actuals -> RMSE / MAE / WAPE / bias -> branch guardrails
```

The companion repository owns transformation, data-quality tests,
documentation, lineage, feature contracts, and prediction monitoring. This R
repository owns model fitting, chronological validation, statistical
diagnostics, and forecasting decisions. The repositories remain separate so
that the analytics layer cannot silently redefine model labels, validation
rules, or production decisions.

## Key Features

- Loads warranty claim detail and monthly summaries from MariaDB
- Engineers lag, rolling-average, trend, growth, volatility, and seasonal features
- Compares baseline and year-over-year XGBoost feature sets
- Evaluates forecasts with RMSE, MAE, and MAPE
- Performs walk-forward backtesting for ARIMA, ETS, and XGBoost
- Produces recursive six-month forecasts by branch
- Combines models using inverse-error weights
- Learns adaptive weights by branch and forecast horizon
- Estimates 95% intervals for the automated hybrid forecast
- Creates interactive Plotly model-comparison charts
- Exports the final hybrid forecast to Excel

## Forecasting Architecture

The system combines three complementary forecasting approaches:

- **ARIMA** captures autoregressive and time-series patterns.
- **ETS** models level, trend, and seasonal behavior.
- **XGBoost** uses engineered historical and calendar features.

Walk-forward backtesting measures each model's historical error. The adaptive
hybrid model then assigns weights by service branch and forecast horizon,
allowing short- and medium-term predictions to use different model strengths.

## Feature Engineering

- One-, two-, three-, six-, and twelve-month lags
- Three- and six-month rolling averages
- Month-over-month and year-over-year growth
- Three- and six-month trend measures
- Rolling volatility
- Monthly sine and cosine seasonality
- Warranty claim composition and cost ratios
- Branch and calendar features

## Technology

- R
- MariaDB
- `DBI` and `RMariaDB`
- `dplyr`, `tidyr`, `purrr`, and `lubridate`
- `xgboost`
- `forecast`
- `Metrics`
- `ggplot2` and `plotly`
- `zoo`
- `writexl`

## Project Structure

```text
.
├── scripts/
│   └── warranty_revenue_forecasting.R
├── .env.example
├── .gitignore
└── README.md
```

## Configuration

Set the following environment variables before running the analysis:

```text
MARIADB_HOST
MARIADB_PORT
MARIADB_USER
MARIADB_PASSWORD
MARIADB_DATABASE
MARIADB_DETAIL_TABLE
MARIADB_MONTHLY_TABLE
REPORT_OUTPUT_DIR
```

See `.env.example` for non-secret example values.

## Installation

```r
install.packages(c(
  "readxl", "dplyr", "stringr", "purrr", "lubridate", "hms",
  "zoo", "xgboost", "Metrics", "ggplot2", "tidyr", "plotly",
  "forecast", "tibble", "DBI", "RMariaDB", "writexl"
))
```

## Running the Forecast

After configuring the database and environment variables:

```r
source("scripts/warranty_revenue_forecasting.R", encoding = "UTF-8")
```

The script is an exploratory forecasting workflow and expects the configured
tables to provide the fields used in the feature-engineering sections.

## Main Outputs

- XGBoost model-performance comparison
- Feature-importance charts
- Walk-forward backtesting metrics
- ARIMA, ETS, and recursive XGBoost forecasts
- Branch-level adaptive hybrid forecasts
- Forecast uncertainty intervals
- Interactive branch and model comparison charts
- Excel forecast report

## Data Privacy

Do not commit warranty claim records, internal branch mappings, database
credentials, financial reports, or generated forecasts. Use synthetic or
anonymized data when demonstrating the workflow.
