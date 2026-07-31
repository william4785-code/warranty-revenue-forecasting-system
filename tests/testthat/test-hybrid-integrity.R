test_that("common-key validation catches missing models", {
  sample <- tidyr::crossing(
    branch_id = "B01",
    origin = as.Date("2026-01-01"),
    date = as.Date("2026-02-01"),
    h = 1L,
    model = c("ARIMA", "ETS", "XGB")
  ) |>
    dplyr::mutate(actual = 100, pred = c(90, 95, 105))

  expect_true(assert_backtest_common_keys(sample))
  expect_error(
    assert_backtest_common_keys(dplyr::filter(sample, model != "XGB")),
    "common-key"
  )
})

test_that("Hybrid weights are estimated only from prior origins", {
  origins <- as.Date(c("2026-01-01", "2026-02-01", "2026-03-01"))
  sample <- tidyr::crossing(
    branch_id = "B01",
    origin = origins,
    h = 1L,
    model = c("ARIMA", "ETS", "XGB")
  ) |>
    dplyr::mutate(
      date = .data$origin %m+% months(1),
      actual = 100,
      pred = dplyr::case_when(
        .data$model == "ARIMA" ~ 90,
        .data$model == "ETS" ~ 95,
        TRUE ~ 105
      )
    )

  hybrid <- build_hybrid_backtest(sample)
  first <- dplyr::filter(hybrid, origin == min(origin))
  later <- dplyr::filter(hybrid, origin > min(origin))

  expect_equal(first$weight_source, "equal_weight_cold_start")
  expect_true(all(grepl("^prior_branch", later$weight_source)))
})
