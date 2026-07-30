inverse_rmse_weights <- function(errors, expected_models) {
  model_rmse <- errors |>
    dplyr::group_by(.data$model) |>
    dplyr::summarise(
      RMSE = sqrt(mean((.data$actual - .data$pred)^2)),
      n = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::filter(
      .data$model %in% expected_models,
      is.finite(.data$RMSE),
      .data$RMSE > 0
    )

  if (!setequal(model_rmse$model, expected_models)) {
    return(tibble::tibble(
      model = expected_models,
      weight = rep(1 / length(expected_models), length(expected_models))
    ))
  }

  model_rmse |>
    dplyr::mutate(
      inv_rmse = 1 / .data$RMSE,
      weight = .data$inv_rmse / sum(.data$inv_rmse)
    ) |>
    dplyr::select("model", "weight")
}

weights_before_origin <- function(
    backtest,
    branch_id,
    h,
    origin,
    expected_models,
    min_horizon_rows = 2L) {
  prior <- backtest |>
    dplyr::filter(
      .data$branch_id == .env$branch_id,
      .data$origin < .env$origin
    )

  prior_h <- dplyr::filter(prior, .data$h == .env$h)
  horizon_counts <- prior_h |>
    dplyr::count(.data$model)

  if (
    nrow(horizon_counts) == length(expected_models) &&
      all(horizon_counts$n >= min_horizon_rows)
  ) {
    weights <- inverse_rmse_weights(prior_h, expected_models)
    weights$weight_source <- "prior_branch_h"
    return(weights)
  }

  if (nrow(prior) > 0L) {
    weights <- inverse_rmse_weights(prior, expected_models)
    weights$weight_source <- "prior_branch"
    return(weights)
  }

  tibble::tibble(
    model = expected_models,
    weight = rep(1 / length(expected_models), length(expected_models)),
    weight_source = "equal_weight_cold_start"
  )
}

build_hybrid_backtest <- function(
    backtest,
    expected_models = c("ARIMA", "ETS", "XGB")) {
  assert_backtest_common_keys(backtest, expected_models)
  keys <- backtest |>
    dplyr::distinct(.data$branch_id, .data$origin, .data$date, .data$h) |>
    dplyr::arrange(.data$branch_id, .data$origin, .data$h)

  weighted_rows <- vector("list", nrow(keys))

  for (i in seq_len(nrow(keys))) {
    key <- keys[i, ]
    weights <- weights_before_origin(
      backtest,
      branch_id = key$branch_id,
      h = key$h,
      origin = key$origin,
      expected_models = expected_models
    )

    weighted_rows[[i]] <- backtest |>
      dplyr::filter(
        .data$branch_id == key$branch_id,
        .data$origin == key$origin,
        .data$date == key$date,
        .data$h == key$h
      ) |>
      dplyr::left_join(weights, by = "model") |>
      dplyr::rename(weight_final = "weight")
  }

  hybrid_input <- dplyr::bind_rows(weighted_rows) |>
    dplyr::group_by(.data$branch_id, .data$date, .data$h) |>
    dplyr::mutate(
      weight_final = .data$weight_final / sum(.data$weight_final)
    ) |>
    dplyr::ungroup()

  if (anyNA(hybrid_input$weight_final)) {
    stop("Hybrid backtest contains missing weights.", call. = FALSE)
  }
  assert_weight_sums(hybrid_input)

  hybrid_input |>
    dplyr::mutate(weighted_pred = .data$pred * .data$weight_final) |>
    dplyr::group_by(
      .data$branch_id, .data$origin, .data$date,
      .data$h, .data$actual
    ) |>
    dplyr::summarise(
      pred = sum(.data$weighted_pred),
      weight_source = paste(sort(unique(.data$weight_source)), collapse = "+"),
      model = "Hybrid",
      .groups = "drop"
    )
}

final_hybrid_weights <- function(
    backtest,
    branch_id,
    h,
    expected_models) {
  horizon_errors <- backtest |>
    dplyr::filter(
      .data$branch_id == .env$branch_id,
      .data$h == .env$h
    )

  if (
    length(unique(horizon_errors$model)) == length(expected_models) &&
      min(table(horizon_errors$model)) >= 2L
  ) {
    weights <- inverse_rmse_weights(horizon_errors, expected_models)
    weights$weight_source <- "all_backtest_branch_h"
    return(weights)
  }

  branch_errors <- backtest |>
    dplyr::filter(.data$branch_id == .env$branch_id)
  weights <- inverse_rmse_weights(branch_errors, expected_models)
  weights$weight_source <- "all_backtest_branch"
  weights
}

hybrid_error_scale <- function(hybrid_backtest) {
  by_h <- hybrid_backtest |>
    dplyr::group_by(.data$branch_id, .data$h) |>
    dplyr::summarise(
      hybrid_rmse_h = sqrt(mean((.data$actual - .data$pred)^2)),
      n_h = dplyr::n(),
      .groups = "drop"
    )

  by_branch <- hybrid_backtest |>
    dplyr::group_by(.data$branch_id) |>
    dplyr::summarise(
      hybrid_rmse_branch = sqrt(mean((.data$actual - .data$pred)^2)),
      n_branch = dplyr::n(),
      .groups = "drop"
    )

  dplyr::left_join(by_h, by_branch, by = "branch_id") |>
    dplyr::mutate(
      hybrid_rmse = dplyr::if_else(
        .data$n_h >= 3L,
        .data$hybrid_rmse_h,
        .data$hybrid_rmse_branch
      ),
      interval_source = dplyr::if_else(
        .data$n_h >= 3L,
        "branch_h_residual",
        "branch_residual_fallback"
      )
    ) |>
    dplyr::select(
      "branch_id", "h", "hybrid_rmse",
      "interval_source", "n_h", "n_branch"
    )
}

combine_final_forecasts <- function(
    component_forecasts,
    backtest,
    hybrid_backtest,
    expected_models = c("ARIMA", "ETS", "XGB")) {
  keys <- component_forecasts |>
    dplyr::distinct(.data$branch_id, .data$date, .data$h)
  weighted_rows <- vector("list", nrow(keys))

  for (i in seq_len(nrow(keys))) {
    key <- keys[i, ]
    weights <- final_hybrid_weights(
      backtest,
      key$branch_id,
      key$h,
      expected_models
    )
    weighted_rows[[i]] <- component_forecasts |>
      dplyr::filter(
        .data$branch_id == key$branch_id,
        .data$date == key$date,
        .data$h == key$h
      ) |>
      dplyr::left_join(weights, by = "model") |>
      dplyr::rename(weight_final = "weight")
  }

  hybrid_input <- dplyr::bind_rows(weighted_rows) |>
    dplyr::group_by(.data$branch_id, .data$date, .data$h) |>
    dplyr::mutate(
      weight_final = .data$weight_final / sum(.data$weight_final)
    ) |>
    dplyr::ungroup()

  if (anyNA(hybrid_input$weight_final)) {
    stop("Final Hybrid contains missing weights.", call. = FALSE)
  }
  assert_weight_sums(hybrid_input)

  scale <- hybrid_error_scale(hybrid_backtest)

  hybrid_input |>
    dplyr::mutate(weighted_pred = .data$pred * .data$weight_final) |>
    dplyr::group_by(
      .data$branch_id, .data$date, .data$h,
      .data$weight_source
    ) |>
    dplyr::summarise(
      pred = sum(.data$weighted_pred),
      model = "Hybrid",
      .groups = "drop"
    ) |>
    dplyr::left_join(scale, by = c("branch_id", "h")) |>
    dplyr::mutate(
      lower95 = pmax(0, .data$pred - 1.96 * .data$hybrid_rmse),
      upper95 = .data$pred + 1.96 * .data$hybrid_rmse
    )
}
