select_backtest_origins <- function(
    branch_data,
    h_max,
    n_origins,
    min_history = 30L) {
  n <- nrow(branch_data)
  last_origin <- n - h_max
  first_origin <- max(min_history, last_origin - n_origins + 1L)

  if (last_origin < first_origin) {
    return(integer())
  }

  seq.int(first_origin, last_origin)
}

walk_forward_backtest <- function(
    data,
    config = portfolio_config(),
    n_origins = 6L) {
  assert_monthly_schema(data)
  data <- dplyr::arrange(data, .data$branch_id, .data$date)
  branch_frames <- split(data, data$branch_id)
  all_results <- list()
  result_index <- 0L

  for (branch_data in branch_frames) {
    branch_data <- dplyr::arrange(branch_data, .data$date)
    origins <- select_backtest_origins(
      branch_data,
      h_max = config$horizon,
      n_origins = n_origins,
      min_history = max(18L, minimum_rows_for_route(
        unique(branch_data$branch_id), config
      ) + 12L)
    )

    for (origin_index in origins) {
      history <- branch_data[seq_len(origin_index), , drop = FALSE]
      origin_date <- max(history$date)
      actual <- branch_data[
        origin_index + seq_len(config$horizon),
        c("date", "revenue"),
        drop = FALSE
      ]

      stat_fc <- forecast_statistical_models(
        history,
        h_max = config$horizon
      )
      xgb_fc <- forecast_xgb_recursive(
        history,
        h_max = config$horizon,
        config = config
      )

      combined <- dplyr::bind_rows(
        stat_fc |>
          dplyr::select(
            "date", "branch_id", "h", "model", "pred"
          ),
        xgb_fc |>
          dplyr::select(
            "date", "branch_id", "h", "model", "pred"
          )
      ) |>
        dplyr::left_join(
          dplyr::rename(actual, actual = "revenue"),
          by = "date"
        ) |>
        dplyr::mutate(
          origin = origin_date,
          max_train_date = origin_date
        ) |>
        dplyr::select(
          "origin", "date", "branch_id",
          "h", "model", "actual", "pred", "max_train_date"
        )

      result_index <- result_index + 1L
      all_results[[result_index]] <- combined
    }
  }

  output <- dplyr::bind_rows(all_results)
  assert_backtest_common_keys(output, config$expected_models)
  assert_prediction_chronology(output)
  output
}
