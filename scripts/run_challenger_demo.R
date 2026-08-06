suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(zoo)
  library(xgboost)
  library(forecast)
  library(tibble)
})

source("R/pipeline.R", encoding = "UTF-8")
source_portfolio_modules(".")
source("R/synthetic_data.R", encoding = "UTF-8")

demo_data <- generate_synthetic_warranty_data(
  n_months = as.integer(Sys.getenv("CHALLENGER_MONTHS", "72"))
)
control <- portfolio_config(
  horizon = as.integer(Sys.getenv("CHALLENGER_HORIZON", "6")),
  nrounds = 20L,
  min_train_rows = 20L,
  short_history_rows = 9L
)
candidate_specs <- list(
  shallow_regularized = list(
    nrounds = 12L,
    params = list(
      eta = 0.03,
      max_depth = 2L,
      min_child_weight = 8,
      subsample = 0.85,
      colsample_bytree = 1,
      lambda = 5,
      alpha = 1
    )
  ),
  balanced = list(
    nrounds = 20L,
    params = list(
      eta = 0.05,
      max_depth = 3L,
      min_child_weight = 3,
      subsample = 0.85,
      colsample_bytree = 0.85,
      lambda = 3,
      alpha = 0
    )
  ),
  deeper = list(
    nrounds = 28L,
    params = list(
      eta = 0.05,
      max_depth = 5L,
      min_child_weight = 1,
      subsample = 0.8,
      colsample_bytree = 0.8,
      lambda = 1,
      alpha = 0
    )
  )
)

result <- run_fixed_challenger_holdout(
  demo_data,
  candidate_specs = candidate_specs,
  control_config = control,
  n_origins = as.integer(Sys.getenv("CHALLENGER_ORIGINS", "8")),
  branch_guardrail = 5
)

output_dir <- Sys.getenv("REPORT_OUTPUT_DIR", "outputs/challenger_demo")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  result$development_scores,
  file.path(output_dir, "development_scores.csv"),
  row.names = FALSE
)
utils::write.csv(
  result$promotion_gates,
  file.path(output_dir, "promotion_gates.csv"),
  row.names = FALSE
)

cat("\nSynthetic fixed-Challenger holdout completed.\n")
cat("Selected candidate:", result$selected_candidate, "\n")
cat("Decision:", result$decision, "\n\n")
print(result$promotion_gates, n = Inf)
cat(
  "\nSynthetic outcomes are structural demonstrations, not production evidence.\n"
)
