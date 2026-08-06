test_that("chronological split freezes development before test", {
  split <- chronological_origin_split(seq(
    as.Date("2025-01-01"),
    by = "1 month",
    length.out = 8L
  ))
  expect_equal(length(split$development), 4L)
  expect_equal(length(split$test), 4L)
  expect_lt(max(split$development), min(split$test))
})

test_that("failed downstream gates retain the Champion", {
  result <- promotion_gate_table(
    xgb_change_pct = 9.60,
    hybrid_change_pct = 3.64,
    improved_horizon_n = 2L,
    branch_changes_pct = c(-27.0, 15.6, 9.4, 0.2),
    nowcast_changes_pct = c(2.19, 2.73, 0.61, -1.63, 0.02),
    fallback_unchanged = TRUE,
    branch_guardrail = 5
  )
  expect_equal(result$decision, "RETAIN_CHAMPION")
  expect_false(all(result$gates$passed))
})

test_that("prediction comparison rejects mismatched evaluation keys", {
  control <- tibble(
    branch_id = "B01", origin = as.Date("2025-01-01"),
    date = as.Date("2025-02-01"), h = 1L, actual = 10, pred = 9
  )
  challenger <- mutate(control, date = as.Date("2025-03-01"))
  expect_error(
    compare_prediction_sets(control, challenger),
    "identical evaluation keys"
  )
})
