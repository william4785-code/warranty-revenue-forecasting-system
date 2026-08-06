forecast_metrics <- function(actual, pred) {
  keep <- stats::complete.cases(actual, pred)
  actual <- actual[keep]
  pred <- pred[keep]

  if (length(actual) == 0L) {
    return(tibble::tibble(
      RMSE = NA_real_, MAE = NA_real_, MAPE = NA_real_,
      WAPE = NA_real_, Bias = NA_real_, n = 0L
    ))
  }

  error <- pred - actual
  non_zero <- actual != 0

  tibble::tibble(
    RMSE = sqrt(mean(error^2)),
    MAE = mean(abs(error)),
    MAPE = if (any(non_zero)) {
      mean(abs(error[non_zero] / actual[non_zero])) * 100
    } else {
      NA_real_
    },
    WAPE = if (sum(abs(actual)) > 0) {
      sum(abs(error)) / sum(abs(actual)) * 100
    } else {
      NA_real_
    },
    Bias = mean(error),
    n = length(actual)
  )
}

evaluate_backtest <- function(backtest) {
  backtest |>
    dplyr::group_by(.data$branch_id, .data$model, .data$h) |>
    dplyr::group_modify(
      ~ forecast_metrics(.x$actual, .x$pred)
    ) |>
    dplyr::ungroup()
}
