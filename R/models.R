fit_xgb <- function(train_features, feature_names, config) {
  assert_no_leakage_features(feature_names)

  complete <- stats::complete.cases(
    train_features[c(feature_names, "revenue")]
  )
  train_complete <- train_features[complete, , drop = FALSE]

  if (nrow(train_complete) == 0L) {
    stop("No complete XGBoost training rows.", call. = FALSE)
  }

  set.seed(config$seed)
  xgboost::xgb.train(
    params = config$xgb_params,
    data = xgboost::xgb.DMatrix(
      data = as.matrix(train_complete[, feature_names, drop = FALSE]),
      label = train_complete$revenue
    ),
    nrounds = config$nrounds,
    verbose = 0
  )
}

forecast_xgb_recursive <- function(
    history,
    h_max = 6L,
    config = portfolio_config()) {
  branch_id <- unique(history$branch_id)
  if (length(branch_id) != 1L) {
    stop("XGBoost history must contain exactly one branch.", call. = FALSE)
  }

  history <- dplyr::arrange(history, .data$date)
  engineered <- engineer_monthly_features(history)
  history_values <- history$revenue
  last_date <- max(history$date)
  model_cache <- list()
  output <- vector("list", h_max)

  for (h in seq_len(h_max)) {
    route <- xgb_feature_route(branch_id, h)
    assert_no_leakage_features(route$features)

    minimum_rows <- minimum_rows_for_route(branch_id, config)
    complete_n <- sum(stats::complete.cases(
      engineered[c(route$features, "revenue")]
    ))
    if (complete_n < minimum_rows) {
      stop(
        sprintf(
          "Branch %s route %s has %s complete rows; %s required.",
          branch_id, route$name, complete_n, minimum_rows
        ),
        call. = FALSE
      )
    }

    if (is.null(model_cache[[route$name]])) {
      model_cache[[route$name]] <- fit_xgb(
        engineered,
        route$features,
        config
      )
    }

    future_date <- last_date %m+% lubridate::period(h, units = "month")
    new_row <- recursive_feature_row(history_values, future_date)
    pred <- predict(
      model_cache[[route$name]],
      xgboost::xgb.DMatrix(
        as.matrix(new_row[, route$features, drop = FALSE])
      )
    )
    history_values <- c(history_values, as.numeric(pred))

    output[[h]] <- tibble::tibble(
      date = future_date,
      branch_id = branch_id,
      h = h,
      model = "XGB",
      pred = as.numeric(pred),
      xgb_feature_version = route$name,
      xgb_feature_n = length(route$features)
    )
  }

  dplyr::bind_rows(output)
}

forecast_statistical_models <- function(history, h_max = 6L) {
  branch_id <- unique(history$branch_id)
  if (length(branch_id) != 1L) {
    stop("History must contain exactly one branch.", call. = FALSE)
  }

  history <- dplyr::arrange(history, .data$date)
  last_date <- max(history$date)
  y <- stats::ts(history$revenue, frequency = 12)

  arima_fit <- forecast::auto.arima(y, allowdrift = TRUE)
  ets_fit <- forecast::ets(y)
  arima_fc <- forecast::forecast(arima_fit, h = h_max)
  ets_fc <- forecast::forecast(ets_fit, h = h_max)
  future_dates <- seq(
    from = last_date %m+% lubridate::period(1L, units = "month"),
    by = "1 month",
    length.out = h_max
  )

  dplyr::bind_rows(
    tibble::tibble(
      date = future_dates,
      branch_id = branch_id,
      h = seq_len(h_max),
      model = "ARIMA",
      pred = as.numeric(arima_fc$mean),
      lower80 = as.numeric(arima_fc$lower[, 1L]),
      upper80 = as.numeric(arima_fc$upper[, 1L]),
      lower95 = as.numeric(arima_fc$lower[, 2L]),
      upper95 = as.numeric(arima_fc$upper[, 2L])
    ),
    tibble::tibble(
      date = future_dates,
      branch_id = branch_id,
      h = seq_len(h_max),
      model = "ETS",
      pred = as.numeric(ets_fc$mean),
      lower80 = as.numeric(ets_fc$lower[, 1L]),
      upper80 = as.numeric(ets_fc$upper[, 1L]),
      lower95 = as.numeric(ets_fc$lower[, 2L]),
      upper95 = as.numeric(ets_fc$upper[, 2L])
    )
  )
}
