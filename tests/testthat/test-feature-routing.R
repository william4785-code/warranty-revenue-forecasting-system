test_that("all public routes exclude blocked forecast-time features", {
  for (branch_id in sprintf("B%02d", 1:5)) {
    for (h in 1:6) {
      route <- xgb_feature_route(branch_id, h)
      expect_true(assert_no_leakage_features(route$features))
    }
  }
})

test_that("routing policy is horizon aware", {
  expect_equal(xgb_feature_route("B01", 1)$name, "recursive_core")
  expect_equal(xgb_feature_route("B01", 6)$name, "safe_compact")
  expect_equal(
    xgb_feature_route("B02", 6)$name,
    "recursive_core_guardrail"
  )
  expect_equal(
    xgb_feature_route("B05", 6)$name,
    "recursive_core_short_history"
  )
})

test_that("short-history branch has an explicit threshold", {
  config <- portfolio_config()
  expect_equal(minimum_rows_for_route("B05", config), 9L)
  expect_equal(minimum_rows_for_route("B01", config), 24L)
})
