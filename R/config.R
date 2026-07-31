# Portfolio V2.2 configuration -----------------------------------------------

portfolio_config <- function(
    horizon = 6L,
    nrounds = 80L,
    min_train_rows = 24L,
    short_history_rows = 9L,
    seed = 20260717L) {
  list(
    horizon = as.integer(horizon),
    nrounds = as.integer(nrounds),
    min_train_rows = as.integer(min_train_rows),
    short_history_rows = as.integer(short_history_rows),
    seed = as.integer(seed),
    expected_models = c("ARIMA", "ETS", "XGB"),
    xgb_params = list(
      objective = "reg:squarederror",
      eval_metric = "rmse",
      eta = 0.05,
      max_depth = 4L,
      min_child_weight = 3,
      subsample = 0.8,
      colsample_bytree = 0.8,
      nthread = 1L
    )
  )
}

core_features <- function() {
  c(
    "month", "quarter", "year",
    "lag1_revenue", "lag2_revenue", "lag3_revenue",
    "rolling3_revenue", "rolling6_revenue",
    "trend_3m", "growth_1m", "volatility_3m",
    "sin_month", "cos_month"
  )
}

safe_compact_features <- function() {
  c(
    core_features(),
    "lag6_revenue", "lag12_revenue",
    "trend_6m", "growth_3m", "volatility_6m"
  )
}

# Synthetic branch IDs illustrate routing behavior without exposing production
# locations. B02 is a guardrail route and B05 demonstrates short-history
# fallback. These IDs have no mapping to real service branches.
xgb_feature_route <- function(branch_id, h) {
  stopifnot(length(branch_id) == 1L, length(h) == 1L, h >= 1L)

  if (identical(branch_id, "B02")) {
    return(list(
      name = "recursive_core_guardrail",
      features = core_features()
    ))
  }

  if (identical(branch_id, "B05")) {
    return(list(
      name = "recursive_core_short_history",
      features = core_features()
    ))
  }

  if (h <= 4L) {
    return(list(name = "recursive_core", features = core_features()))
  }

  list(name = "safe_compact", features = safe_compact_features())
}

minimum_rows_for_route <- function(branch_id, config = portfolio_config()) {
  if (identical(branch_id, "B05")) {
    config$short_history_rows
  } else {
    config$min_train_rows
  }
}
