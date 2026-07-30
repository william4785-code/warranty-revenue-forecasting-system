test_that("synthetic data has a valid anonymous schema", {
  data <- generate_synthetic_warranty_data(n_months = 36L)

  expect_true(assert_monthly_schema(data))
  expect_setequal(unique(data$branch_id), sprintf("B%02d", 1:5))
  expect_false(any(grepl("^A[0-9]+$", data$branch_id)))
})

test_that("open month is excluded", {
  data <- tibble::tibble(
    date = as.Date(c("2026-06-01", "2026-07-01")),
    branch_id = c("B01", "B01"),
    revenue = c(100, 200)
  )

  result <- exclude_open_month(data, as.Date("2026-07-15"))
  expect_equal(result$date, as.Date("2026-06-01"))
})

test_that("duplicate monthly keys fail loudly", {
  data <- tibble::tibble(
    date = as.Date(c("2026-01-01", "2026-01-01")),
    branch_id = c("B01", "B01"),
    revenue = c(100, 200)
  )

  expect_error(assert_monthly_schema(data), "Duplicate")
})
