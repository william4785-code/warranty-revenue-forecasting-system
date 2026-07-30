safe_sd <- function(x) {
  if (sum(!is.na(x)) < 2L) return(NA_real_)
  stats::sd(x, na.rm = TRUE)
}

engineer_monthly_features <- function(data) {
  assert_monthly_schema(data)

  data |>
    dplyr::arrange(.data$branch_id, .data$date) |>
    dplyr::group_by(.data$branch_id) |>
    dplyr::mutate(
      month = lubridate::month(.data$date),
      quarter = lubridate::quarter(.data$date),
      year = lubridate::year(.data$date),
      lag1_revenue = dplyr::lag(.data$revenue, 1L),
      lag2_revenue = dplyr::lag(.data$revenue, 2L),
      lag3_revenue = dplyr::lag(.data$revenue, 3L),
      lag6_revenue = dplyr::lag(.data$revenue, 6L),
      lag12_revenue = dplyr::lag(.data$revenue, 12L),
      rolling3_revenue = zoo::rollapply(
        dplyr::lag(.data$revenue, 1L),
        width = 3L,
        FUN = mean,
        align = "right",
        fill = NA_real_,
        na.rm = TRUE
      ),
      rolling6_revenue = zoo::rollapply(
        dplyr::lag(.data$revenue, 1L),
        width = 6L,
        FUN = mean,
        align = "right",
        fill = NA_real_,
        na.rm = TRUE
      ),
      trend_3m = .data$lag1_revenue - .data$lag3_revenue,
      trend_6m = .data$lag1_revenue - .data$lag6_revenue,
      growth_1m = dplyr::if_else(
        !is.na(.data$lag2_revenue) & .data$lag2_revenue != 0,
        (.data$lag1_revenue - .data$lag2_revenue) / .data$lag2_revenue,
        NA_real_
      ),
      growth_3m = dplyr::if_else(
        !is.na(.data$lag3_revenue) & .data$lag3_revenue != 0,
        (.data$lag1_revenue - .data$lag3_revenue) / .data$lag3_revenue,
        NA_real_
      ),
      volatility_3m = zoo::rollapply(
        dplyr::lag(.data$revenue, 1L),
        width = 3L,
        FUN = safe_sd,
        align = "right",
        fill = NA_real_
      ),
      volatility_6m = zoo::rollapply(
        dplyr::lag(.data$revenue, 1L),
        width = 6L,
        FUN = safe_sd,
        align = "right",
        fill = NA_real_
      ),
      sin_month = sin(2 * pi * .data$month / 12),
      cos_month = cos(2 * pi * .data$month / 12)
    ) |>
    dplyr::ungroup()
}

recursive_feature_row <- function(history_values, future_date) {
  if (length(history_values) < 12L) {
    stop("At least 12 history values are required.", call. = FALSE)
  }

  lag_value <- function(k) {
    history_values[length(history_values) - k + 1L]
  }

  lag1 <- lag_value(1L)
  lag2 <- lag_value(2L)
  lag3 <- lag_value(3L)
  lag6 <- lag_value(6L)
  lag12 <- lag_value(12L)

  tibble::tibble(
    month = lubridate::month(future_date),
    quarter = lubridate::quarter(future_date),
    year = lubridate::year(future_date),
    lag1_revenue = lag1,
    lag2_revenue = lag2,
    lag3_revenue = lag3,
    lag6_revenue = lag6,
    lag12_revenue = lag12,
    rolling3_revenue = mean(utils::tail(history_values, 3L)),
    rolling6_revenue = mean(utils::tail(history_values, 6L)),
    trend_3m = lag1 - lag3,
    trend_6m = lag1 - lag6,
    growth_1m = if (lag2 == 0) NA_real_ else (lag1 - lag2) / lag2,
    growth_3m = if (lag3 == 0) NA_real_ else (lag1 - lag3) / lag3,
    volatility_3m = safe_sd(utils::tail(history_values, 3L)),
    volatility_6m = safe_sd(utils::tail(history_values, 6L)),
    sin_month = sin(2 * pi * lubridate::month(future_date) / 12),
    cos_month = cos(2 * pi * lubridate::month(future_date) / 12)
  )
}
