# Application-progress nowcast ----------------------------------------------

nowcast_metric_frame <- function(data) {
  forecast_metrics(data$actual, data$pred)
}

application_progress_history <- function(applications, cutoff_days) {
  completed_monthly <- applications |>
    dplyr::mutate(month = lubridate::floor_date(
      .data$application_date,
      unit = "month"
    )) |>
    dplyr::group_by(.data$branch_id, .data$month) |>
    dplyr::summarise(
      actual = sum(.data$amount),
      application_n = dplyr::n_distinct(.data$application_id),
      .groups = "drop"
    )

  progress <- tidyr::crossing(
    completed_monthly,
    cutoff_day = cutoff_days
  ) |>
    dplyr::mutate(
      cutoff_date = .data$month + lubridate::days(.data$cutoff_day - 1L)
    ) |>
    dplyr::select(
      "branch_id", "month", "cutoff_day", "cutoff_date",
      "actual", "application_n"
    )

  cumulative <- applications |>
    dplyr::mutate(month = lubridate::floor_date(
      .data$application_date,
      unit = "month"
    )) |>
    dplyr::inner_join(
      dplyr::select(
        progress,
        "branch_id", "month", "cutoff_day", "cutoff_date"
      ),
      by = c("branch_id", "month"),
      relationship = "many-to-many"
    ) |>
    dplyr::filter(.data$application_date <= .data$cutoff_date) |>
    dplyr::group_by(
      .data$branch_id, .data$month,
      .data$cutoff_day, .data$cutoff_date
    ) |>
    dplyr::summarise(
      cumulative_amount = sum(.data$amount),
      cumulative_application_n = dplyr::n_distinct(.data$application_id),
      .groups = "drop"
    )

  progress |>
    dplyr::left_join(
      cumulative,
      by = c("branch_id", "month", "cutoff_day", "cutoff_date")
    ) |>
    dplyr::mutate(
      cumulative_amount = dplyr::coalesce(.data$cumulative_amount, 0),
      cumulative_application_n = dplyr::coalesce(
        .data$cumulative_application_n,
        0L
      ),
      observed_share = dplyr::if_else(
        .data$actual > 0,
        pmin(1, pmax(0, .data$cumulative_amount / .data$actual)),
        NA_real_
      )
    )
}

add_prior_progress_curves <- function(progress, branch_curve_shrinkage) {
  branch_prior <- progress |>
    dplyr::arrange(.data$branch_id, .data$cutoff_day, .data$month) |>
    dplyr::group_by(.data$branch_id, .data$cutoff_day) |>
    dplyr::mutate(
      branch_history_n = dplyr::row_number() - 1L,
      branch_share_prior = dplyr::lag(cummean(.data$observed_share))
    ) |>
    dplyr::ungroup() |>
    dplyr::select(
      "branch_id", "month", "cutoff_day",
      "branch_history_n", "branch_share_prior"
    )

  pooled <- progress |>
    dplyr::group_by(.data$month, .data$cutoff_day) |>
    dplyr::summarise(
      pooled_observed_share = sum(.data$cumulative_amount) /
        sum(.data$actual),
      .groups = "drop"
    ) |>
    dplyr::arrange(.data$cutoff_day, .data$month) |>
    dplyr::group_by(.data$cutoff_day) |>
    dplyr::mutate(
      pooled_history_n = dplyr::row_number() - 1L,
      pooled_share_prior = dplyr::lag(cummean(.data$pooled_observed_share))
    ) |>
    dplyr::ungroup() |>
    dplyr::select(
      "month", "cutoff_day", "pooled_history_n", "pooled_share_prior"
    )

  progress |>
    dplyr::left_join(
      branch_prior,
      by = c("branch_id", "month", "cutoff_day")
    ) |>
    dplyr::left_join(pooled, by = c("month", "cutoff_day")) |>
    dplyr::mutate(
      calendar_share_fallback = .data$cutoff_day /
        lubridate::days_in_month(.data$month),
      pooled_share_prior = dplyr::coalesce(
        .data$pooled_share_prior,
        .data$calendar_share_fallback
      ),
      branch_share_prior = dplyr::coalesce(
        .data$branch_share_prior,
        .data$pooled_share_prior
      ),
      branch_curve_weight = .data$branch_history_n /
        (.data$branch_history_n + branch_curve_shrinkage),
      blended_share = pmax(
        0.05,
        .data$branch_curve_weight * .data$branch_share_prior +
          (1 - .data$branch_curve_weight) * .data$pooled_share_prior
      ),
      curve_pred = pmax(0, .data$cumulative_amount / .data$blended_share)
    )
}

select_prior_only_blend_weights <- function(
    history,
    cutoff_days,
    minimum_training_rows,
    weight_grid = seq(0, 1, by = 0.05)) {
  target_months <- sort(unique(history$month))
  output <- list()
  index <- 0L

  for (cutoff in cutoff_days) {
    cutoff_history <- dplyr::filter(history, .data$cutoff_day == cutoff)
    for (month_index in seq_along(target_months)) {
      target_month <- target_months[[month_index]]
      train <- cutoff_history |>
        dplyr::filter(
          .data$month < target_month,
          is.finite(.data$actual),
          is.finite(.data$baseline_pred),
          is.finite(.data$curve_pred)
        )
      if (nrow(train) < minimum_training_rows) {
        best_weight <- 0
        source <- "insufficient_history_baseline_only"
        best_rmse <- NA_real_
      } else {
        scores <- vapply(weight_grid, function(weight) {
          pred <- (1 - weight) * train$baseline_pred +
            weight * train$curve_pred
          sqrt(mean((train$actual - pred)^2))
        }, numeric(1L))
        best <- which.min(scores)
        best_weight <- weight_grid[[best]]
        best_rmse <- scores[[best]]
        source <- "prior_months_rmse"
      }
      index <- index + 1L
      output[[index]] <- tibble::tibble(
        cutoff_day = cutoff,
        month = target_month,
        curve_weight = best_weight,
        training_n = nrow(train),
        training_last_month = if (nrow(train) > 0L) {
          max(train$month)
        } else {
          as.Date(NA)
        },
        training_rmse = best_rmse,
        weight_source = source
      )
    }
  }
  dplyr::bind_rows(output)
}

build_application_progress_nowcast <- function(
    applications,
    forecast_h1,
    hybrid_backtest,
    as_of_date = Sys.Date(),
    cutoff_days = c(5L, 10L, 15L, 20L, 25L),
    fallback_branches = character(),
    minimum_blend_training_rows = 8L,
    branch_curve_shrinkage = 6,
    minimum_branch_interval_rows = 5L) {
  assert_application_schema(applications)
  as_of_date <- as.Date(as_of_date)
  if (is.na(as_of_date)) stop("Invalid as_of_date.", call. = FALSE)
  cutoff_days <- sort(unique(as.integer(cutoff_days)))
  if (length(cutoff_days) == 0L || any(cutoff_days < 1L | cutoff_days > 31L)) {
    stop("cutoff_days must be calendar days from 1 to 31.", call. = FALSE)
  }

  open_month <- lubridate::floor_date(as_of_date, unit = "month")
  completed_applications <- dplyr::filter(
    applications,
    .data$application_date < open_month
  )
  progress <- application_progress_history(
    completed_applications,
    cutoff_days
  ) |>
    add_prior_progress_curves(branch_curve_shrinkage)

  baseline_h1 <- hybrid_backtest |>
    dplyr::filter(.data$h == 1L) |>
    dplyr::transmute(
      branch_id = .data$branch_id,
      month = as.Date(.data$date),
      baseline_actual = .data$actual,
      baseline_pred = .data$pred
    )
  if (anyDuplicated(baseline_h1[c("branch_id", "month")])) {
    stop("Hybrid h=1 baseline contains duplicate keys.", call. = FALSE)
  }

  history <- progress |>
    dplyr::inner_join(baseline_h1, by = c("branch_id", "month"))
  reconciliation <- history |>
    dplyr::distinct(
      .data$branch_id, .data$month,
      .data$actual, .data$baseline_actual
    ) |>
    dplyr::summarise(
      common_key_n = dplyr::n(),
      exact_match_n = sum(abs(.data$actual - .data$baseline_actual) < 1e-6),
      max_abs_diff = max(abs(.data$actual - .data$baseline_actual)),
      .groups = "drop"
    )
  if (
    nrow(reconciliation) == 0L ||
      reconciliation$common_key_n[[1L]] != reconciliation$exact_match_n[[1L]]
  ) {
    stop("Application totals do not reconcile with h=1 backtest actuals.", call. = FALSE)
  }

  blend_log <- select_prior_only_blend_weights(
    history,
    cutoff_days,
    minimum_blend_training_rows
  )
  backtest <- history |>
    dplyr::left_join(blend_log, by = c("cutoff_day", "month")) |>
    dplyr::mutate(
      pred = (1 - .data$curve_weight) * .data$baseline_pred +
        .data$curve_weight * .data$curve_pred,
      model = "Application-progress Nowcast"
    )
  metrics <- backtest |>
    dplyr::group_by(.data$cutoff_day) |>
    dplyr::group_modify(~ nowcast_metric_frame(.x)) |>
    dplyr::ungroup()

  interval_branch <- backtest |>
    dplyr::group_by(.data$branch_id, .data$cutoff_day) |>
    dplyr::summarise(
      nowcast_rmse_branch = sqrt(mean((.data$actual - .data$pred)^2)),
      interval_n_branch = dplyr::n(),
      .groups = "drop"
    )
  interval_global <- backtest |>
    dplyr::group_by(.data$cutoff_day) |>
    dplyr::summarise(
      nowcast_rmse_global = sqrt(mean((.data$actual - .data$pred)^2)),
      .groups = "drop"
    )

  forecast <- forecast_h1 |>
    dplyr::filter(.data$h == 1L, as.Date(.data$date) == open_month) |>
    dplyr::transmute(
      date = as.Date(.data$date),
      branch_id = .data$branch_id,
      h = .data$h,
      baseline_pred = .data$pred,
      baseline_lower95 = .data$lower95,
      baseline_upper95 = .data$upper95
    )
  if (nrow(forecast) == 0L) {
    stop("Open-month Hybrid h=1 forecast is missing.", call. = FALSE)
  }

  available <- cutoff_days[cutoff_days <= lubridate::day(as_of_date)]
  selected_cutoff <- if (length(available)) max(available) else NA_integer_
  if (is.na(selected_cutoff)) {
    current <- forecast |>
      dplyr::mutate(
        as_of_date = as_of_date,
        cutoff_day = NA_integer_,
        cumulative_amount = NA_real_,
        curve_weight = 0,
        pred = .data$baseline_pred,
        lower95 = .data$baseline_lower95,
        upper95 = .data$baseline_upper95,
        nowcast_status = "before_first_cutoff_baseline_only"
      )
    return(list(
      current = current,
      backtest = backtest,
      metrics = metrics,
      blend_selection_log = blend_log,
      reconciliation = reconciliation
    ))
  }

  cutoff_date <- open_month + lubridate::days(selected_cutoff - 1L)
  current_cumulative <- applications |>
    dplyr::filter(
      .data$application_date >= open_month,
      .data$application_date <= cutoff_date
    ) |>
    dplyr::group_by(.data$branch_id) |>
    dplyr::summarise(
      cumulative_amount = sum(.data$amount),
      cumulative_application_n = dplyr::n_distinct(.data$application_id),
      .groups = "drop"
    )
  current_prior <- progress |>
    dplyr::filter(.data$cutoff_day == selected_cutoff) |>
    dplyr::group_by(.data$branch_id) |>
    dplyr::slice_max(.data$month, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(
      "branch_id", "blended_share", "branch_history_n",
      "pooled_history_n"
    )
  current_training <- dplyr::filter(
    backtest,
    .data$cutoff_day == selected_cutoff
  )
  if (nrow(current_training) < minimum_blend_training_rows) {
    current_weight <- 0
    weight_source <- "insufficient_history_baseline_only"
  } else {
    weight_grid <- seq(0, 1, by = 0.05)
    scores <- vapply(weight_grid, function(weight) {
      pred <- (1 - weight) * current_training$baseline_pred +
        weight * current_training$curve_pred
      sqrt(mean((current_training$actual - pred)^2))
    }, numeric(1L))
    current_weight <- weight_grid[[which.min(scores)]]
    weight_source <- "prior_completed_months_rmse"
  }
  validated_branches <- baseline_h1 |>
    dplyr::count(.data$branch_id, name = "baseline_backtest_n") |>
    dplyr::filter(
      .data$baseline_backtest_n >= minimum_blend_training_rows,
      !.data$branch_id %in% fallback_branches
    )

  current <- forecast |>
    dplyr::left_join(current_cumulative, by = "branch_id") |>
    dplyr::left_join(current_prior, by = "branch_id") |>
    dplyr::left_join(validated_branches, by = "branch_id") |>
    dplyr::left_join(
      dplyr::filter(interval_branch, .data$cutoff_day == selected_cutoff),
      by = "branch_id"
    ) |>
    dplyr::mutate(
      as_of_date = as_of_date,
      cutoff_day = selected_cutoff,
      cumulative_amount = dplyr::coalesce(.data$cumulative_amount, 0),
      curve_pred = pmax(0, .data$cumulative_amount / .data$blended_share),
      is_validated_branch = !is.na(.data$baseline_backtest_n),
      curve_weight = dplyr::if_else(
        .data$is_validated_branch,
        current_weight,
        0
      ),
      pred = (1 - .data$curve_weight) * .data$baseline_pred +
        .data$curve_weight * .data$curve_pred,
      nowcast_rmse = dplyr::if_else(
        .data$interval_n_branch >= minimum_branch_interval_rows,
        .data$nowcast_rmse_branch,
        interval_global$nowcast_rmse_global[
          interval_global$cutoff_day == selected_cutoff
        ][[1L]]
      ),
      lower95 = dplyr::if_else(
        .data$is_validated_branch,
        pmax(0, .data$pred - 1.96 * .data$nowcast_rmse),
        .data$baseline_lower95
      ),
      upper95 = dplyr::if_else(
        .data$is_validated_branch,
        .data$pred + 1.96 * .data$nowcast_rmse,
        .data$baseline_upper95
      ),
      weight_source = weight_source,
      nowcast_status = dplyr::case_when(
        .data$branch_id %in% fallback_branches ~
          "baseline_only_short_history_fallback",
        !.data$is_validated_branch ~ "baseline_only_branch_not_backtested",
        .data$curve_weight == 0 ~ "validated_cutoff_baseline_weight_zero",
        TRUE ~ "application_progress_blend"
      )
    ) |>
    dplyr::select(
      "as_of_date", "date", "branch_id", "h", "cutoff_day",
      "cumulative_amount", "cumulative_application_n",
      "baseline_pred", "curve_pred", "curve_weight", "pred",
      "lower95", "upper95", "weight_source", "nowcast_status"
    )

  list(
    current = current,
    backtest = backtest,
    metrics = metrics,
    blend_selection_log = blend_log,
    reconciliation = reconciliation
  )
}
