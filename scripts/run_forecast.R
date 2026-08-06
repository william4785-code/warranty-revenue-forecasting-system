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
application_data <- load_optional_application_input()
analysis_as_of <- as.Date(Sys.getenv(
  "ANALYSIS_AS_OF_DATE",
  format(Sys.Date(), "%Y-%m-%d")
))
results <- run_forecasting_pipeline(
  monthly_data,
  as_of_date = analysis_as_of,
  application_data = application_data
)

output_dir <- Sys.getenv("REPORT_OUTPUT_DIR", "outputs")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

writexl::write_xlsx(
  list(
    hybrid_forecast = results$hybrid_forecast,
    component_forecasts = results$component_forecasts,
    component_metrics = results$component_metrics,
    hybrid_metrics = results$hybrid_metrics,
    current_nowcast = if (!is.null(results$nowcast)) {
      results$nowcast$current
    } else {
      data.frame(status = "application input not supplied")
    }
  ),
  file.path(output_dir, "portfolio_v2_3_forecast.xlsx")
)

print(results$hybrid_forecast, n = Inf)
