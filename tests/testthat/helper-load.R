suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(zoo)
  library(xgboost)
  library(forecast)
  library(tibble)
})

project_root <- normalizePath(
  file.path(getwd(), "..", ".."),
  winslash = "/",
  mustWork = TRUE
)

source(file.path(project_root, "R", "pipeline.R"), encoding = "UTF-8")
source_portfolio_modules(project_root)
source(
  file.path(project_root, "R", "synthetic_data.R"),
  encoding = "UTF-8"
)
