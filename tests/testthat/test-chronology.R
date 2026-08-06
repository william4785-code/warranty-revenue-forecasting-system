test_that("chronology audit accepts only prior training dates", {
  valid <- tibble(
    origin = as.Date(c("2025-01-01", "2025-01-01")),
    date = as.Date(c("2025-02-01", "2025-03-01")),
    h = c(1L, 2L),
    max_train_date = as.Date(c("2025-01-01", "2025-01-01"))
  )
  expect_invisible(assert_prediction_chronology(valid))
  invalid <- mutate(valid, max_train_date = as.Date("2025-04-01"))
  expect_error(assert_prediction_chronology(invalid), "chronology")
})
