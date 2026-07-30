suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(zoo)
  library(xgboost)
  library(forecast)
  library(tibble)
  library(ggplot2)
  library(writexl)
})

source("R/pipeline.R", encoding = "UTF-8")
source_portfolio_modules(".")
source("R/synthetic_data.R", encoding = "UTF-8")

demo_config <- portfolio_config(
  horizon = as.integer(Sys.getenv("DEMO_HORIZON", "6")),
  nrounds = as.integer(Sys.getenv("DEMO_NROUNDS", "40")),
  min_train_rows = 24L,
  short_history_rows = 9L
)

demo_data <- generate_synthetic_warranty_data()
demo_results <- run_forecasting_pipeline(
  demo_data,
  config = demo_config,
  n_origins = as.integer(Sys.getenv("DEMO_ORIGINS", "4")),
  as_of_date = as.Date("2030-01-01")
)

output_dir <- Sys.getenv("REPORT_OUTPUT_DIR", "outputs/demo")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

if (tolower(Sys.getenv("DEMO_WRITE_EXCEL", "true")) == "true") {
  writexl::write_xlsx(
    list(
      synthetic_input = demo_data,
      hybrid_forecast = demo_results$hybrid_forecast,
      component_metrics = demo_results$component_metrics,
      hybrid_metrics = demo_results$hybrid_metrics
    ),
    file.path(output_dir, "synthetic_demo_results.xlsx")
  )
}

plot_data <- dplyr::bind_rows(
  demo_data |>
    dplyr::transmute(
      date = .data$date,
      branch_id = .data$branch_id,
      series = "History",
      value = .data$revenue
    ),
  demo_results$hybrid_forecast |>
    dplyr::transmute(
      date = .data$date,
      branch_id = .data$branch_id,
      series = "Hybrid forecast",
      value = .data$pred
    )
)

forecast_plot <- ggplot(
  plot_data,
  aes(x = .data$date, y = .data$value, color = .data$series)
) +
  geom_line(linewidth = 0.7) +
  facet_wrap(~branch_id, scales = "free_y") +
  scale_y_continuous(labels = scales::label_number(big.mark = ",")) +
  labs(
    title = "Synthetic warranty revenue: history and Hybrid forecast",
    subtitle = "Portfolio demonstration only - no company data",
    x = NULL,
    y = "Synthetic revenue",
    color = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top")

ggsave(
  file.path(output_dir, "synthetic_forecast.png"),
  forecast_plot,
  width = 12,
  height = 7,
  dpi = 160
)

cat("\nPortfolio V2.2 synthetic demo completed.\n")
cat("Output directory:", normalizePath(output_dir), "\n")
print(demo_results$hybrid_forecast, n = 12)
