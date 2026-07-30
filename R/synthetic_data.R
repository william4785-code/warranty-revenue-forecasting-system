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
