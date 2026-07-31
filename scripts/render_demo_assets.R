old_output <- Sys.getenv("REPORT_OUTPUT_DIR", unset = NA_character_)
old_rounds <- Sys.getenv("DEMO_NROUNDS", unset = NA_character_)
old_origins <- Sys.getenv("DEMO_ORIGINS", unset = NA_character_)
old_horizon <- Sys.getenv("DEMO_HORIZON", unset = NA_character_)
old_write_excel <- Sys.getenv("DEMO_WRITE_EXCEL", unset = NA_character_)

on.exit({
  if (is.na(old_output)) Sys.unsetenv("REPORT_OUTPUT_DIR") else Sys.setenv(REPORT_OUTPUT_DIR = old_output)
  if (is.na(old_rounds)) Sys.unsetenv("DEMO_NROUNDS") else Sys.setenv(DEMO_NROUNDS = old_rounds)
  if (is.na(old_origins)) Sys.unsetenv("DEMO_ORIGINS") else Sys.setenv(DEMO_ORIGINS = old_origins)
  if (is.na(old_horizon)) Sys.unsetenv("DEMO_HORIZON") else Sys.setenv(DEMO_HORIZON = old_horizon)
  if (is.na(old_write_excel)) Sys.unsetenv("DEMO_WRITE_EXCEL") else Sys.setenv(DEMO_WRITE_EXCEL = old_write_excel)
}, add = TRUE)

Sys.setenv(
  REPORT_OUTPUT_DIR = "docs/assets",
  DEMO_NROUNDS = "25",
  DEMO_ORIGINS = "3",
  DEMO_HORIZON = "6",
  DEMO_WRITE_EXCEL = "false"
)

source("scripts/run_demo.R", encoding = "UTF-8")
