test_that("application-progress nowcast uses prior data and preserves fallback", {
  monthly <- generate_synthetic_warranty_data(
    start_date = as.Date("2023-01-01"),
    n_months = 30L,
    branches = c("B01", "B05")
  )
  open_month <- max(monthly$date) %m+% months(1L)
  applications <- generate_synthetic_applications(
    monthly,
    open_month = open_month,
    as_of_day = 20L
  )
  baseline_months <- monthly$date[7:30]
  baseline <- tidyr::crossing(
    branch_id = c("B01", "B05"),
    date = baseline_months
  ) |>
    left_join(monthly, by = c("branch_id", "date")) |>
    transmute(
      branch_id, date, h = 1L,
      actual = revenue,
      pred = revenue * 1.02,
      origin = date %m-% months(1L),
      model = "Hybrid"
    )
  forecast <- tibble(
    date = open_month,
    branch_id = c("B01", "B05"),
    h = 1L,
    pred = c(900000, 1100000),
    lower95 = c(700000, 850000),
    upper95 = c(1100000, 1350000)
  )

  result <- build_application_progress_nowcast(
    applications,
    forecast,
    baseline,
    as_of_date = open_month + days(19L),
    fallback_branches = "B05",
    minimum_blend_training_rows = 6L
  )

  expect_equal(nrow(result$current), 2L)
  expect_equal(
    result$current$nowcast_status[result$current$branch_id == "B05"],
    "baseline_only_short_history_fallback"
  )
  expect_equal(
    result$current$pred[result$current$branch_id == "B05"],
    result$current$baseline_pred[result$current$branch_id == "B05"]
  )
  trained <- result$blend_selection_log |>
    filter(!is.na(training_last_month))
  expect_true(all(trained$training_last_month < trained$month))
})

test_that("dates before the first cutoff keep the Hybrid baseline", {
  monthly <- generate_synthetic_warranty_data(
    start_date = as.Date("2023-01-01"),
    n_months = 24L,
    branches = "B01"
  )
  open_month <- max(monthly$date) %m+% months(1L)
  applications <- generate_synthetic_applications(monthly, open_month, 3L)
  baseline <- monthly[7:24, ] |>
    transmute(
      branch_id, date, h = 1L, actual = revenue,
      pred = revenue, origin = date %m-% months(1L), model = "Hybrid"
    )
  forecast <- tibble(
    date = open_month, branch_id = "B01", h = 1L,
    pred = 100, lower95 = 80, upper95 = 120
  )
  result <- build_application_progress_nowcast(
    applications,
    forecast,
    baseline,
    as_of_date = open_month + days(2L),
    minimum_blend_training_rows = 6L
  )
  expect_equal(result$current$pred, 100)
  expect_equal(
    result$current$nowcast_status,
    "before_first_cutoff_baseline_only"
  )
})
