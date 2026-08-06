source_portfolio_modules <- function(root = ".") {
  module_order <- c(
    "config.R",
    "data_validation.R",
    "feature_engineering.R",
    "metrics.R",
    "models.R",
    "backtesting.R",
    "hybrid.R",
    "nowcast.R",
    "challenger_validation.R",
    "io.R"
  )
  invisible(lapply(
    file.path(root, "R", module_order),
    source,
    local = globalenv(),
    encoding = "UTF-8"
  ))
}

run_forecasting_pipeline <- function(
    monthly_data,
    config = portfolio_config(),
    n_origins = 6L,
    as_of_date = Sys.Date(),
    application_data = NULL) {
  monthly_data <- exclude_open_month(monthly_data, as_of_date)
  assert_monthly_schema(monthly_data)

  backtest <- walk_forward_backtest(
    monthly_data,
    config = config,
    n_origins = n_origins
  )
  hybrid_backtest <- build_hybrid_backtest(
    backtest,
    config$expected_models
  )

  component_forecasts <- monthly_data |>
    split(monthly_data$branch_id) |>
    lapply(function(branch_data) {
      dplyr::bind_rows(
        forecast_statistical_models(branch_data, config$horizon) |>
          dplyr::select(
            "date", "branch_id", "h", "model", "pred"
          ),
        forecast_xgb_recursive(
          branch_data,
          h_max = config$horizon,
          config = config
        ) |>
          dplyr::select(
            "date", "branch_id", "h", "model", "pred",
            "xgb_feature_version", "xgb_feature_n"
          )
      )
    }) |>
    dplyr::bind_rows()

  hybrid_forecast <- combine_final_forecasts(
    component_forecasts,
    backtest,
    hybrid_backtest,
    config$expected_models
  )

  result <- list(
    backtest = backtest,
    component_metrics = evaluate_backtest(backtest),
    hybrid_backtest = hybrid_backtest,
    hybrid_metrics = evaluate_backtest(hybrid_backtest),
    component_forecasts = component_forecasts,
    hybrid_forecast = hybrid_forecast
  )

  if (!is.null(application_data)) {
    result$nowcast <- build_application_progress_nowcast(
      applications = application_data,
      forecast_h1 = hybrid_forecast,
      hybrid_backtest = hybrid_backtest,
      as_of_date = as_of_date,
      cutoff_days = config$nowcast_cutoffs,
      fallback_branches = config$nowcast_fallback_branches,
      minimum_blend_training_rows = config$nowcast_min_training_rows,
      branch_curve_shrinkage = config$nowcast_curve_shrinkage
    )
  }

  result
}
