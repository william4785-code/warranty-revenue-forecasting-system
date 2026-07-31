suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(zoo)
  library(xgboost)
  library(forecast)
  library(tibble)
  library(DBI)
  library(RMariaDB)
  library(writexl)
})

source("R/pipeline.R", encoding = "UTF-8")
source_portfolio_modules(".")

monthly_data <- load_portfolio_input()
results <- run_forecasting_pipeline(monthly_data)

output_dir <- Sys.getenv("REPORT_OUTPUT_DIR", "outputs")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

writexl::write_xlsx(
  list(
    hybrid_forecast = results$hybrid_forecast,
    component_forecasts = results$component_forecasts,
    component_metrics = results$component_metrics,
    hybrid_metrics = results$hybrid_metrics
  ),
  file.path(output_dir, "portfolio_v2_2_forecast.xlsx")
)

print(results$hybrid_forecast, n = Inf)
