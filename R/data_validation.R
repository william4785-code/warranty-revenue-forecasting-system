required_monthly_columns <- function() {
  c("date", "branch_id", "revenue")
}

required_application_columns <- function() {
  c("application_id", "branch_id", "application_date", "amount")
}

assert_application_schema <- function(data) {
  missing_columns <- setdiff(required_application_columns(), names(data))
  if (length(missing_columns) > 0L) {
    stop(
      "Missing required application columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  if (!inherits(data$application_date, "Date")) {
    stop("`application_date` must be a Date column.", call. = FALSE)
  }
  if (!is.numeric(data$amount)) {
    stop("`amount` must be numeric.", call. = FALSE)
  }
  if (anyNA(data[required_application_columns()])) {
    stop("Required application columns contain missing values.", call. = FALSE)
  }
  if (anyDuplicated(data$application_id)) {
    stop("Duplicate application_id values detected.", call. = FALSE)
  }
  if (any(data$amount < 0)) {
    stop("Application amounts must be non-negative.", call. = FALSE)
  }
  invisible(TRUE)
}

assert_prediction_chronology <- function(data) {
  required <- c("origin", "date", "h", "max_train_date")
  missing_columns <- setdiff(required, names(data))
  if (length(missing_columns) > 0L) {
    stop(
      "Chronology audit is missing: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  bad <- data |>
    dplyr::mutate(
      observed_h =
        (lubridate::year(.data$date) - lubridate::year(.data$origin)) * 12L +
        lubridate::month(.data$date) - lubridate::month(.data$origin)
    ) |>
    dplyr::filter(
      .data$max_train_date > .data$origin |
        .data$origin >= .data$date |
        .data$observed_h != .data$h
    )
  if (nrow(bad) > 0L) {
    stop("Prediction chronology validation failed.", call. = FALSE)
  }
  invisible(TRUE)
}

assert_monthly_schema <- function(data) {
  missing_columns <- setdiff(required_monthly_columns(), names(data))
  if (length(missing_columns) > 0L) {
    stop(
      "Missing required columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  if (!inherits(data$date, "Date")) {
    stop("`date` must be a Date column.", call. = FALSE)
  }

  if (!is.numeric(data$revenue)) {
    stop("`revenue` must be numeric.", call. = FALSE)
  }

  duplicated_keys <- duplicated(data[c("date", "branch_id")])
  if (any(duplicated_keys)) {
    stop("Duplicate date x branch_id keys detected.", call. = FALSE)
  }

  if (anyNA(data[c("date", "branch_id", "revenue")])) {
    stop("Required columns contain missing values.", call. = FALSE)
  }

  invisible(TRUE)
}

exclude_open_month <- function(data, as_of_date = Sys.Date()) {
  open_month <- lubridate::floor_date(as.Date(as_of_date), unit = "month")
  dplyr::filter(data, .data$date < open_month)
}

assert_no_leakage_features <- function(feature_names) {
  blocked <- c(
    "yoy_growth_revenue",
    "same_month_claim_count",
    "same_month_category_a_count",
    "same_month_category_b_count"
  )
  found <- intersect(feature_names, blocked)
  if (length(found) > 0L) {
    stop(
      "Forecast-time unavailable features detected: ",
      paste(found, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

assert_backtest_common_keys <- function(
    backtest,
    expected_models = c("ARIMA", "ETS", "XGB")) {
  check <- backtest |>
    dplyr::group_by(.data$branch_id, .data$origin, .data$date, .data$h) |>
    dplyr::summarise(
      n_rows = dplyr::n(),
      n_models = dplyr::n_distinct(.data$model),
      n_actual = dplyr::n_distinct(.data$actual),
      missing_pred = any(is.na(.data$pred)),
      duplicated_model = anyDuplicated(.data$model) > 0L,
      model_set_ok = setequal(.data$model, expected_models),
      .groups = "drop"
    ) |>
    dplyr::filter(
      .data$n_rows != length(expected_models) |
        .data$n_models != length(expected_models) |
        .data$n_actual != 1L |
        .data$missing_pred |
        .data$duplicated_model |
        !.data$model_set_ok
    )

  if (nrow(check) > 0L) {
    print(utils::head(check, 20L))
    stop("Backtest common-key validation failed.", call. = FALSE)
  }

  invisible(TRUE)
}

assert_weight_sums <- function(data, tolerance = 1e-8) {
  bad <- data |>
    dplyr::group_by(.data$branch_id, .data$date, .data$h) |>
    dplyr::summarise(weight_sum = sum(.data$weight_final), .groups = "drop") |>
    dplyr::filter(abs(.data$weight_sum - 1) > tolerance)

  if (nrow(bad) > 0L) {
    print(utils::head(bad, 20L))
    stop("Hybrid weights do not sum to one.", call. = FALSE)
  }

  invisible(TRUE)
}
