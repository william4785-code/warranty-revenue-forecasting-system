generate_synthetic_warranty_data <- function(
    start_date = as.Date("2019-01-01"),
    n_months = 84L,
    branches = sprintf("B%02d", 1:5),
    seed = 20260717L) {
  set.seed(seed)
  dates <- seq(start_date, by = "1 month", length.out = n_months)

  branch_profiles <- tibble::tibble(
    branch_id = branches,
    base = seq(650000, 1250000, length.out = length(branches)),
    trend = seq(4500, 12000, length.out = length(branches)),
    seasonal_scale = seq(90000, 180000, length.out = length(branches)),
    noise_scale = seq(70000, 150000, length.out = length(branches))
  )

  tidyr::crossing(
    date = dates,
    branch_profiles
  ) |>
    dplyr::group_by(.data$branch_id) |>
    dplyr::mutate(
      month_index = dplyr::row_number(),
      seasonal = .data$seasonal_scale * sin(
        2 * pi * lubridate::month(.data$date) / 12
      ),
      campaign = dplyr::if_else(
        lubridate::month(.data$date) %in% c(3L, 7L, 11L),
        0.10 * .data$base,
        0
      ),
      regime = dplyr::if_else(
        .data$date >= as.Date("2024-01-01"),
        0.14 * .data$base,
        0
      ),
      revenue = pmax(
        10000,
        .data$base +
          .data$trend * .data$month_index +
          .data$seasonal +
          .data$campaign +
          .data$regime +
          stats::rnorm(dplyr::n(), 0, .data$noise_scale)
      ),
      claim_count = pmax(
        1L,
        round(.data$revenue / 24000 + stats::rnorm(dplyr::n(), 0, 3))
      ),
      category_a_count = pmax(
        0L,
        round(.data$claim_count * runif(dplyr::n(), 0.35, 0.55))
      ),
      category_b_count = pmax(
        0L,
        round(.data$claim_count * runif(dplyr::n(), 0.15, 0.30))
      )
    ) |>
    dplyr::ungroup() |>
    dplyr::select(
      "date", "branch_id", "revenue",
      "claim_count", "category_a_count",
      "category_b_count"
    )
}

generate_synthetic_applications <- function(
    monthly_data,
    open_month = max(monthly_data$date) %m+%
      lubridate::period(1L, units = "month"),
    as_of_day = 20L,
    seed = 20260806L) {
  assert_monthly_schema(monthly_data)
  set.seed(seed)

  completed <- monthly_data |>
    dplyr::select("date", "branch_id", "revenue", "claim_count")
  open_stub <- completed |>
    dplyr::group_by(.data$branch_id) |>
    dplyr::summarise(
      date = as.Date(open_month),
      revenue = mean(utils::tail(.data$revenue, 3L)) *
        stats::runif(1L, 0.92, 1.08),
      claim_count = max(12L, round(mean(utils::tail(.data$claim_count, 3L)))),
      .groups = "drop"
    )
  source <- dplyr::bind_rows(completed, open_stub)

  rows <- vector("list", nrow(source))
  for (i in seq_len(nrow(source))) {
    row <- source[i, ]
    n <- as.integer(max(5L, row$claim_count))
    month_days <- lubridate::days_in_month(row$date)
    days <- sort(sample.int(month_days, n, replace = TRUE))
    raw_amounts <- stats::rgamma(length(days), shape = 2.5, rate = 1)
    amounts <- raw_amounts * (row$revenue / sum(raw_amounts))
    if (row$date == as.Date(open_month)) {
      observed <- days <= as.integer(as_of_day)
      days <- days[observed]
      amounts <- amounts[observed]
      if (length(days) == 0L) {
        days <- as.integer(as_of_day)
        amounts <- row$revenue * as_of_day / month_days
      }
    }
    rows[[i]] <- tibble::tibble(
      application_id = sprintf(
        "SYN-%s-%s-%04d",
        row$branch_id,
        format(row$date, "%Y%m"),
        seq_along(days)
      ),
      branch_id = row$branch_id,
      application_date = as.Date(row$date) + days - 1L,
      amount = amounts
    )
  }
  dplyr::bind_rows(rows)
}
