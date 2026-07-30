test_that("small synthetic pipeline produces complete forecasts", {
  data <- generate_synthetic_warranty_data(
    n_months = 48L,
    branches = c("B01", "B02")
  )
  config <- portfolio_config(
    horizon = 2L,
    nrounds = 5L,
    min_train_rows = 18L
  )

  result <- run_forecasting_pipeline(
    data,
    config = config,
    n_origins = 2L,
    as_of_date = as.Date("2030-01-01")
  )

  expect_equal(nrow(result$hybrid_forecast), 4L)
  expect_false(anyNA(result$hybrid_forecast$pred))
  expect_true(all(result$hybrid_forecast$lower95 >= 0))
  expect_setequal(
    unique(result$component_forecasts$model),
    c("ARIMA", "ETS", "XGB")
  )
})
