
#Warranty Revenue forecast system V2

library(readxl)
library(dplyr)
library(stringr)
library(purrr)
library(lubridate)
library(hms)
library(zoo)
library(xgboost)
library(Metrics)
library(ggplot2)
library(tidyr)
library(plotly)
library(forecast)
library(tibble)
library(DBI)
library(RMariaDB)
library(writexl)

get_required_env <- function(name) {
  value <- Sys.getenv(name, unset = NA_character_)
  if (is.na(value) || !nzchar(value)) {
    stop(sprintf("Missing required environment variable: %s", name), call. = FALSE)
  }
  value
}

connect_mariadb <- function(dbname) {
  mariadb_port <- as.integer(Sys.getenv("MARIADB_PORT", "3306"))
  if (is.na(mariadb_port)) {
    stop("MARIADB_PORT must be a valid integer", call. = FALSE)
  }

  DBI::dbConnect(
    RMariaDB::MariaDB(),
    host = Sys.getenv("MARIADB_HOST", "127.0.0.1"),
    port = mariadb_port,
    user = get_required_env("MARIADB_USER"),
    password = get_required_env("MARIADB_PASSWORD"),
    dbname = dbname
  )
}

close_mariadb <- function(con) {
  tryCatch(
    {
      if (DBI::dbIsValid(con)) {
        DBI::dbDisconnect(con)
      }
    },
    error = function(e) invisible(FALSE)
  )
}

load_warranty_data <- function() {
  detail_table <- Sys.getenv("MARIADB_DETAIL_TABLE", "warranty_claim_detail")
  monthly_table <- Sys.getenv("MARIADB_MONTHLY_TABLE", "warranty_claim_monthly")
  table_names <- c(detail_table, monthly_table)
  if (any(!str_detect(table_names, "^[A-Za-z0-9_]+$"))) {
    stop("MariaDB table names may contain only letters, numbers, and underscores", call. = FALSE)
  }

  con <- connect_mariadb(Sys.getenv("MARIADB_DATABASE", "warranty_analytics"))
  on.exit(close_mariadb(con), add = TRUE)

  df_all <- DBI::dbGetQuery(con, sprintf("SELECT * FROM `%s`", detail_table))

  monthly_df <- DBI::dbGetQuery(con, sprintf("SELECT * FROM `%s`", monthly_table))

  list(df_all = df_all, monthly_df = monthly_df)
}

warranty_data <- load_warranty_data()
df_all <- warranty_data$df_all
monthly_df <- warranty_data$monthly_df
rm(warranty_data)

model_base <- monthly_df %>%
  mutate(
    總案件數 = 對策案件數 + 保證內案件數,

    `310占比` = if_else(保證內案件數 > 0, `310件數` / 保證內案件數, NA_real_),
    `412占比` = if_else(保證內案件數 > 0, `412件數` / 保證內案件數, NA_real_),
    超保占比 = if_else(保證內案件數 > 0, 超保件數 / 保證內案件數, NA_real_),
    對策占比 = if_else(總案件數 > 0, 對策案件數 / 總案件數, NA_real_),

    零件占比 = if_else(申請總金額 > 0, 更換零件金額 / 申請總金額, NA_real_),
    工資占比 = if_else(申請總金額 > 0, 工資 / 申請總金額, NA_real_),
    外包占比 = if_else(申請總金額 > 0, 外包金額 / 申請總金額, NA_real_),

    month = month(年月),
    quarter = quarter(年月),
    year = year(年月)
  )

model_df_final <- model_base %>%
  arrange(據點代號, 年月) %>%
  group_by(據點代號) %>%
  mutate(
    # -------------------------
    # lag features
    # -------------------------
    `lag1_申請總金額`   = lag(申請總金額, 1),
    `lag2_申請總金額`   = lag(申請總金額, 2),
    `lag3_申請總金額`   = lag(申請總金額, 3),
    `lag6_申請總金額` = lag(申請總金額, 6),

    `lag1_310件數`     = lag(`310件數`, 1),
    `lag2_310件數`     = lag(`310件數`, 2),
    `lag3_310件數`     = lag(`310件數`, 3),

    `lag1_412件數`     = lag(`412件數`, 1),
    `lag2_412件數`     = lag(`412件數`, 2),
    `lag3_412件數`     = lag(`412件數`, 3),

    `lag1_對策案件數`   = lag(對策案件數, 1),
    `lag2_對策案件數`   = lag(對策案件數, 2),
    `lag3_對策案件數`   = lag(對策案件數, 3),

    `lag1_保證內案件數` = lag(保證內案件數, 1),
    `lag2_保證內案件數` = lag(保證內案件數, 2),
    `lag3_保證內案件數` = lag(保證內案件數, 3),

    # -------------------------
    # rolling mean
    # 用「過去資料」做平均，不含本月
    # -------------------------
    rolling3_申請總金額 = zoo::rollapply(
      lag(申請總金額, 1),
      width = 3,
      FUN = mean,
      align = "right",
      fill = NA,
      na.rm = TRUE
    ),

    rolling6_申請總金額 = zoo::rollapply(
      lag(申請總金額, 1),
      width = 6,
      FUN = mean,
      align = "right",
      fill = NA,
      na.rm = TRUE
    ),

    rolling3_310件數 = zoo::rollapply(
      lag(`310件數`, 1),
      width = 3,
      FUN = mean,
      align = "right",
      fill = NA,
      na.rm = TRUE
    ),

    rolling6_310件數 = zoo::rollapply(
      lag(`310件數`, 1),
      width = 6,
      FUN = mean,
      align = "right",
      fill = NA,
      na.rm = TRUE
    ),

    rolling3_412件數 = zoo::rollapply(
      lag(`412件數`, 1),
      width = 3,
      FUN = mean,
      align = "right",
      fill = NA,
      na.rm = TRUE
    ),

    rolling6_412件數 = zoo::rollapply(
      lag(`412件數`, 1),
      width = 6,
      FUN = mean,
      align = "right",
      fill = NA,
      na.rm = TRUE
    ),

    # -------------------------
    # YoY / 去年同月
    # -------------------------
    yoy_申請總金額 = lag(申請總金額, 12),
    yoy_310件數   = lag(`310件數`, 12),
    yoy_412件數   = lag(`412件數`, 12),
    yoy_對策案件數 = lag(對策案件數, 12),
    yoy_保證內案件數 = lag(保證內案件數, 12),
    #Trend
    trend_3m = lag1_申請總金額 - lag3_申請總金額,
    trend_6m = lag1_申請總金額 - lag6_申請總金額,
    #Growth
    growth_1m = if_else(
      !is.na(lag2_申請總金額) & lag2_申請總金額 != 0,
      (lag1_申請總金額 - lag2_申請總金額) / lag2_申請總金額,
      NA_real_
    ),

    growth_3m = if_else(
      !is.na(lag3_申請總金額) & lag3_申請總金額 != 0,
      (lag1_申請總金額 - lag3_申請總金額) / lag3_申請總金額,
      NA_real_
    ),
    #Volatility
    volatility_3m = zoo::rollapply(
      lag(申請總金額, 1),
      width = 3,
      FUN = sd,
      align = "right",
      fill = NA,
      na.rm = TRUE
    ),

    volatility_6m = zoo::rollapply(
      lag(申請總金額, 1),
      width = 6,
      FUN = sd,
      align = "right",
      fill = NA,
      na.rm = TRUE
    ),
    #Seasonality
    sin_month = sin(2 * pi * month / 12),
    cos_month = cos(2 * pi * month / 12)
  ) %>%
  ungroup()

model_df_final <- model_df_final %>%
  mutate(
    yoy_growth_申請總金額 = if_else(
      !is.na(yoy_申請總金額) & yoy_申請總金額 != 0,
      (申請總金額 - yoy_申請總金額) / yoy_申請總金額,
      NA_real_
    ),
    yoy_growth_310件數 = if_else(
      !is.na(yoy_310件數) & yoy_310件數 != 0,
      (`310件數` - yoy_310件數) / yoy_310件數,
      NA_real_
    ),
    yoy_growth_412件數 = if_else(
      !is.na(yoy_412件數) & yoy_412件數 != 0,
      (`412件數` - yoy_412件數) / yoy_412件數,
      NA_real_
    )
  )

model_df_final %>%
  select(
    年月, 據點代號, 申請總金額,
    `lag1_申請總金額`, `lag2_申請總金額`, `lag3_申請總金額`,
    rolling3_申請總金額, rolling6_申請總金額,
    yoy_申請總金額, yoy_growth_申請總金額
  ) %>%
  arrange(據點代號, 年月) %>%
  print(n = 40)

model_df_xgb <- model_df_final %>%
  filter(
    !is.na(`lag1_申請總金額`),
    !is.na(`lag2_申請總金額`),
    !is.na(`lag3_申請總金額`),
    !is.na(rolling3_申請總金額),
    !is.na(rolling6_申請總金額),
    !is.na(yoy_申請總金額)
  )

model_data <- model_df_final %>%
  filter(據點代號 %in% c("B01", "B02", "B03", "B04", "B05")) %>%
  arrange(據點代號, 年月)

feature_cols_v1 <- c(
  "month", "quarter", "year",
  "lag1_申請總金額", "lag2_申請總金額", "lag3_申請總金額",
  "lag1_310件數", "lag2_310件數", "lag3_310件數",
  "lag1_412件數", "lag2_412件數", "lag3_412件數",
  "lag1_對策案件數", "lag2_對策案件數", "lag3_對策案件數",
  "lag1_保證內案件數", "lag2_保證內案件數", "lag3_保證內案件數",
  "rolling3_申請總金額", "rolling6_申請總金額",
  "rolling3_310件數", "rolling6_310件數",
  "rolling3_412件數", "rolling6_412件數",
  "trend_3m", "trend_6m",
  "growth_1m", "growth_3m",
  "volatility_3m", "volatility_6m",
  "sin_month", "cos_month"
)

feature_cols_v2 <- c(
  feature_cols_v1,
  "yoy_申請總金額", "yoy_310件數", "yoy_412件數",
  "yoy_對策案件數", "yoy_保證內案件數",
  "yoy_growth_申請總金額",
  "yoy_growth_310件數",
  "yoy_growth_412件數"
)

model_v1 <- model_data %>%
  filter(if_all(all_of(feature_cols_v1), ~ !is.na(.x))) %>%
  mutate(branch_id = case_when(
    據點代號 == "B01" ~ 1,
    據點代號 == "B02" ~ 2,
    據點代號 == "B03" ~ 3,
    據點代號 == "B04" ~ 4,
    據點代號 == "B05" ~ 5,
    TRUE ~ NA_real_
  ))

model_v2 <- model_data %>%
  filter(if_all(all_of(feature_cols_v2), ~ !is.na(.x))) %>%
  mutate(branch_id = case_when(
    據點代號 == "B01" ~ 1,
    據點代號 == "B02" ~ 2,
    據點代號 == "B03" ~ 3,
    據點代號 == "B04" ~ 4,
    據點代號 == "B05" ~ 5,
    TRUE ~ NA_real_
  ))

feature_cols_v1_xgb <- c(feature_cols_v1, "branch_id")
feature_cols_v2_xgb <- c(feature_cols_v2, "branch_id")

model_v1 <- model_v1 %>%
  group_by(據點代號) %>%
  arrange(年月, .by_group = TRUE) %>%
  mutate(
    row_id = row_number(),
    n = n(),
    split_point = floor(n * 0.8)
  ) %>%
  ungroup()

train_v1 <- model_v1 %>%
  filter(row_id <= split_point)

test_v1 <- model_v1 %>%
  filter(row_id > split_point)

model_v2 <- model_v2 %>%
  group_by(據點代號) %>%
  arrange(年月, .by_group = TRUE) %>%
  mutate(
    row_id = row_number(),
    n = n(),
    split_point = floor(n * 0.8)
  ) %>%
  ungroup()

train_v2 <- model_v2 %>%
  filter(row_id <= split_point)

test_v2 <- model_v2 %>%
  filter(row_id > split_point)

train_matrix_v1 <- xgb.DMatrix(
  data = as.matrix(train_v1[, feature_cols_v1_xgb]),
  label = train_v1$申請總金額
)

test_matrix_v1 <- xgb.DMatrix(
  data = as.matrix(test_v1[, feature_cols_v1_xgb]),
  label = test_v1$申請總金額
)

train_matrix_v2 <- xgb.DMatrix(
  data = as.matrix(train_v2[, feature_cols_v2_xgb]),
  label = train_v2$申請總金額
)

test_matrix_v2 <- xgb.DMatrix(
  data = as.matrix(test_v2[, feature_cols_v2_xgb]),
  label = test_v2$申請總金額
)

params <- list(
  objective = "reg:squarederror",
  eval_metric = "rmse",
  eta = 0.05,
  max_depth = 4,
  min_child_weight = 3,
  subsample = 0.8,
  colsample_bytree = 0.8
)

xgb_fit_v1 <- xgb.train(
  params = params,
  data = train_matrix_v1,
  nrounds = 500,
  evals = list(train = train_matrix_v1, test = test_matrix_v1),
  early_stopping_rounds = 30,
  print_every_n = 20
)

xgb_fit_v2 <- xgb.train(
  params = params,
  data = train_matrix_v2,
  nrounds = 500,
  evals = list(train = train_matrix_v2, test = test_matrix_v2),
  early_stopping_rounds = 30,
  print_every_n = 20
)

pred_v1 <- predict(xgb_fit_v1, test_matrix_v1)
rmse_v1 <- rmse(test_v1$申請總金額, pred_v1)
mae_v1  <- mae(test_v1$申請總金額, pred_v1)
mape_v1 <- mean(abs((test_v1$申請總金額 - pred_v1) / test_v1$申請總金額), na.rm = TRUE) * 100

pred_v2 <- predict(xgb_fit_v2, test_matrix_v2)
rmse_v2 <- rmse(test_v2$申請總金額, pred_v2)
mae_v2  <- mae(test_v2$申請總金額, pred_v2)
mape_v2 <- mean(abs((test_v2$申請總金額 - pred_v2) / test_v2$申請總金額), na.rm = TRUE) * 100

result_compare <- tibble::tibble(
  模型版本 = c("v1_穩定版", "v2_YoY完整版"),
  RMSE = c(rmse_v1, rmse_v2),
  MAE  = c(mae_v1, mae_v2),
  MAPE = c(mape_v1, mape_v2)
)

print(result_compare)

imp_v1 <- xgb.importance(
  feature_names = feature_cols_v1_xgb,
  model = xgb_fit_v1
)
print(imp_v1)
imp_v2 <- xgb.importance(
  feature_names = feature_cols_v2_xgb,
  model = xgb_fit_v2
)
print(imp_v2)
imp_v1_df <- imp_v1 %>%
  select(Feature, Gain) %>%
  mutate(model = "V1")

imp_v2_df <- imp_v2 %>%
  select(Feature, Gain) %>%
  mutate(model = "V2")

imp_all <- bind_rows(imp_v1_df, imp_v2_df)

top_features <- imp_all %>%
  group_by(Feature) %>%
  summarise(Gain = max(Gain, na.rm = TRUE)) %>%
  slice_max(order_by = Gain, n = 20) %>%
  pull(Feature)

imp_plot <- imp_all %>%
  filter(Feature %in% top_features)

ggplot(imp_plot, aes(x = reorder(Feature, Gain), y = Gain, fill = model)) +
  geom_col(position = "dodge") +
  coord_flip() +
  labs(
    title = "Feature Importance Comparison (V1 vs V2)",
    x = "Feature",
    y = "Gain",
    fill = "Model"
  ) +
  theme_minimal(base_size = 14)

imp_wide <- imp_all %>%
  pivot_wider(names_from = model, values_from = Gain, values_fill = 0) %>%
  mutate(diff = V2 - V1)

ggplot(imp_wide %>% slice_max(abs(diff), n = 20),
       aes(x = reorder(Feature, diff), y = diff)) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Feature Importance Shift (V2 - V1)",
    x = "Feature",
    y = "Gain Difference"
  ) +
  theme_minimal(base_size = 14)


target_col <- "申請總金額"
branch_list <- c("B01", "B02", "B03", "B04", "B05")
ts_base <- model_df_final %>%
  filter(據點代號 %in% branch_list) %>%
  select(年月, 據點代號, 申請總金額)

#ARIMA Training Set
walk_forward_arima <- function(df_branch, target_col = "申請總金額", min_train = 6, h = 1) {

  df_branch <- df_branch %>%
    arrange(年月) %>%
    filter(!is.na(.data[[target_col]]))

  n <- nrow(df_branch)
  results <- list()

  for (i in seq(min_train, n - h)) {
    train_y <- df_branch[[target_col]][1:i]
    test_y  <- df_branch[[target_col]][(i + h)]
    test_dt <- df_branch$年月[(i + h)]

    fit <- auto.arima(train_y)
    fc  <- forecast(fit, h = h)

    results[[length(results) + 1]] <- tibble(
      年月 = test_dt,
      actual = test_y,
      pred = as.numeric(fc$mean[h])
    )
  }

  bind_rows(results)
}

arima_backtest <- ts_base %>%
  group_split(據點代號) %>%
  map_dfr(function(df_b) {
    branch <- unique(df_b$據點代號)
    walk_forward_arima(df_b) %>%
      mutate(據點代號 = branch, model = "ARIMA")
  })

#ETS Training Set
walk_forward_ets <- function(df_branch, target_col = "申請總金額", min_train = 6, h = 1) {

  df_branch <- df_branch %>%
    arrange(年月) %>%
    filter(!is.na(.data[[target_col]]))

  n <- nrow(df_branch)
  results <- list()

  for (i in seq(min_train, n - h)) {
    train_y <- df_branch[[target_col]][1:i]
    test_y  <- df_branch[[target_col]][(i + h)]
    test_dt <- df_branch$年月[(i + h)]

    fit <- ets(train_y)
    fc  <- forecast(fit, h = h)

    results[[length(results) + 1]] <- tibble(
      年月 = test_dt,
      actual = test_y,
      pred = as.numeric(fc$mean[h])
    )
  }

  bind_rows(results)
}

ets_backtest <- ts_base %>%
  group_split(據點代號) %>%
  map_dfr(function(df_b) {
    branch <- unique(df_b$據點代號)
    walk_forward_ets(df_b) %>%
      mutate(據點代號 = branch, model = "ETS")
  })

#XGBoost Training Set
walk_forward_xgb <- function(df, feature_cols, target_col = "申請總金額", min_train = 10) {

  df <- df %>%
    arrange(年月)

  n <- nrow(df)
  results <- list()

  for (i in seq(min_train, n - 1)) {

    train_df <- df[1:i, ]
    test_df  <- df[i + 1, ]

    # drop NA
    train_df <- train_df %>%
      filter(if_all(all_of(feature_cols), ~ !is.na(.x)))

    test_df <- test_df %>%
      filter(if_all(all_of(feature_cols), ~ !is.na(.x)))

    if (nrow(test_df) == 0) next

    train_matrix <- xgb.DMatrix(
      data = as.matrix(train_df[, feature_cols]),
      label = train_df[[target_col]]
    )

    test_matrix <- xgb.DMatrix(
      data = as.matrix(test_df[, feature_cols])
    )

    fit <- xgb.train(
      params = list(
        objective = "reg:squarederror",
        eval_metric = "rmse",
        eta = 0.05,
        max_depth = 4,
        min_child_weight = 3,
        subsample = 0.8,
        colsample_bytree = 0.8
      ),
      data = train_matrix,
      nrounds = 200,
      verbose = 0
    )

    pred <- predict(fit, test_matrix)

    results[[length(results) + 1]] <- tibble(
      年月 = test_df$年月,
      actual = test_df[[target_col]],
      pred = pred
    )
  }

  bind_rows(results)
}

model_df_xgb_backtest <- model_df_final %>%
  filter(據點代號 %in% c("B01", "B02", "B03", "B04", "B05")) %>%
  mutate(
    branch_id = case_when(
      據點代號 == "B01" ~ 1,
      據點代號 == "B02" ~ 2,
      據點代號 == "B03" ~ 3,
      據點代號 == "B04" ~ 4,
      據點代號 == "B05" ~ 5,
      TRUE ~ NA_real_
    )
  )

xgb_backtest <- model_df_xgb_backtest %>%
  group_split(據點代號) %>%
  purrr::map_dfr(function(df_b) {
    branch <- unique(df_b$據點代號)

    walk_forward_xgb(
      df_b,
      feature_cols = feature_cols_v1_xgb
    ) %>%
      mutate(據點代號 = branch, model = "XGB")
  })

backtest_all <- bind_rows(
  arima_backtest,
  ets_backtest,
  xgb_backtest
)

#Recursive

#ARIMA
forecast_arima_by_branch <- function(df, h = 6, target_col = "申請總金額") {

  df %>%
    filter(據點代號 %in% c("B01", "B02", "B03", "B04", "B05")) %>%
    group_split(據點代號) %>%
    map_dfr(function(df_b) {

      df_b <- df_b %>%
        arrange(年月) %>%
        filter(!is.na(.data[[target_col]]))

      branch <- unique(df_b$據點代號)
      last_date <- max(df_b$年月, na.rm = TRUE)

      y <- ts(df_b[[target_col]], frequency = 12)

      fit <- auto.arima(y, allowdrift = TRUE)
      fc  <- forecast(fit, h = h)

      tibble(
        年月 = seq(from = last_date %m+% months(1), by = "1 month", length.out = h),
        pred = as.numeric(fc$mean),
        lower80 = as.numeric(fc$lower[, 1]),
        upper80 = as.numeric(fc$upper[, 1]),
        lower95 = as.numeric(fc$lower[, 2]),
        upper95 = as.numeric(fc$upper[, 2]),
        據點代號 = branch,
        model = "ARIMA"
      )
    })
}

arima_forecast <- forecast_arima_by_branch(model_df_final, h = 6)
print(arima_forecast)

#ETS
forecast_ets_by_branch <- function(df, h = 6, target_col = "申請總金額") {

  df %>%
    filter(據點代號 %in% c("B01", "B02", "B03", "B04", "B05")) %>%
    group_split(據點代號) %>%
    map_dfr(function(df_b) {

      df_b <- df_b %>%
        arrange(年月) %>%
        filter(!is.na(.data[[target_col]]))

      branch <- unique(df_b$據點代號)
      last_date <- max(df_b$年月, na.rm = TRUE)

      y <- ts(df_b[[target_col]], frequency = 12)

      fit <- ets(y, model = "AAN")
      fc  <- forecast(fit, h = h)

      tibble(
        年月 = seq(from = last_date %m+% months(1), by = "1 month", length.out = h),
        pred = as.numeric(fc$mean),
        lower80 = as.numeric(fc$lower[, 1]),
        upper80 = as.numeric(fc$upper[, 1]),
        lower95 = as.numeric(fc$lower[, 2]),
        upper95 = as.numeric(fc$upper[, 2]),
        據點代號 = branch,
        model = "ETS"
      )
    })
}

ets_forecast <- forecast_ets_by_branch(model_df_final, h = 6)
print(ets_forecast)

#XGBoost
feature_cols_recursive_safe <- c(
  "month", "quarter", "year",
  "lag1_申請總金額",
  "lag2_申請總金額",
  "lag3_申請總金額",
  "rolling3_申請總金額",
  "rolling6_申請總金額",
  "trend_3m",
  "growth_1m",
  "volatility_3m",
  "sin_month",
  "cos_month"
)

model_df_recursive <- model_df_final %>%
  filter(據點代號 %in% c("B01", "B02", "B03", "B04", "B05")) %>%
  arrange(據點代號, 年月) %>%
  group_by(據點代號) %>%
  mutate(
    month = month(年月),
    quarter = quarter(年月),
    year = year(年月),
    lag1_申請總金額 = lag(申請總金額, 1),
    lag2_申請總金額 = lag(申請總金額, 2),
    lag3_申請總金額 = lag(申請總金額, 3),
    rolling3_申請總金額 = zoo::rollapply(
      lag(申請總金額, 1), 3, mean,
      fill = NA, align = "right", na.rm = TRUE
    ),
    rolling6_申請總金額 = zoo::rollapply(
      lag(申請總金額, 1), 6, mean,
      fill = NA, align = "right", na.rm = TRUE
    )
  ) %>%
  ungroup()

forecast_xgb_recursive_single <- function(df_branch, h = 6, target_col = "申請總金額") {

  df_branch <- df_branch %>%
    arrange(年月) %>%
    filter(if_all(all_of(feature_cols_recursive_safe), ~ !is.na(.x)))

  branch <- unique(df_branch$據點代號)

  train_matrix <- xgb.DMatrix(
    data = as.matrix(df_branch[, feature_cols_recursive_safe]),
    label = df_branch[[target_col]]
  )

  fit <- xgb.train(
    params = list(
      objective = "reg:squarederror",
      eval_metric = "rmse",
      eta = 0.05,
      max_depth = 4,
      min_child_weight = 3,
      subsample = 0.8,
      colsample_bytree = 0.8
    ),
    data = train_matrix,
    nrounds = 200,
    verbose = 0
  )

  history_vals <- df_branch[[target_col]]
  last_date <- max(df_branch$年月, na.rm = TRUE)

  results <- vector("list", h)

  for (step in seq_len(h)) {

    future_date <- last_date %m+% months(step)

    new_row <- tibble(
      年月 = future_date,
      month = month(future_date),
      quarter = quarter(future_date),
      year = year(future_date),

      lag1_申請總金額 = tail(history_vals, 1),
      lag2_申請總金額 = tail(history_vals, 2)[1],
      lag3_申請總金額 = tail(history_vals, 3)[1],
      lag6_申請總金額 = tail(history_vals, 6)[1],

      rolling3_申請總金額 = mean(tail(history_vals, 3), na.rm = TRUE),
      rolling6_申請總金額 = mean(tail(history_vals, 6), na.rm = TRUE),

      trend_3m = tail(history_vals, 1) - tail(history_vals, 3)[1],
      trend_6m = tail(history_vals, 1) - tail(history_vals, 6)[1],

      growth_1m = ifelse(
        tail(history_vals, 2)[1] != 0,
        (tail(history_vals, 1) - tail(history_vals, 2)[1]) / tail(history_vals, 2)[1],
        NA_real_
      ),

      growth_3m = ifelse(
        tail(history_vals, 3)[1] != 0,
        (tail(history_vals, 1) - tail(history_vals, 3)[1]) / tail(history_vals, 3)[1],
        NA_real_
      ),

      volatility_3m = sd(tail(history_vals, 3), na.rm = TRUE),
      volatility_6m = sd(tail(history_vals, 6), na.rm = TRUE),

      sin_month = sin(2 * pi * month(future_date) / 12),
      cos_month = cos(2 * pi * month(future_date) / 12)
    )

    pred_matrix <- xgb.DMatrix(
      data = as.matrix(new_row[, feature_cols_recursive_safe])
    )

    pred <- predict(fit, pred_matrix)

    history_vals <- c(history_vals, pred)

    results[[step]] <- tibble(
      年月 = future_date,
      pred = as.numeric(pred),
      據點代號 = branch,
      model = "XGB_recursive"
    )
  }

  bind_rows(results)
}

xgb_forecast <- model_df_recursive %>%
  filter(據點代號 %in% c("B01", "B02", "B03", "B04", "B05")) %>%
  group_split(據點代號) %>%
  purrr::map_dfr(~ forecast_xgb_recursive_single(.x, h = 6))

print(xgb_forecast)

#Forecast_Combine
forecast_all <- bind_rows(
  arima_forecast,
  ets_forecast,
  xgb_forecast
)

print(forecast_all)

history_plot_df <- model_df_final %>%
  filter(據點代號 %in% c("B01", "B02", "B03", "B04", "B05")) %>%
  select(年月, 據點代號, 申請總金額) %>%
  mutate(type = "歷史", value = 申請總金額) %>%
  select(年月, 據點代號, type, value)

forecast_plot_df <- forecast_all %>%
  mutate(type = model, value = pred) %>%
  select(年月, 據點代號, type, value)

plot_df <- bind_rows(history_plot_df, forecast_plot_df)

ggplot(plot_df, aes(x = 年月, y = value, color = type)) +
  geom_line() +
  facet_wrap(~ 據點代號, scales = "free_y") +
  theme_minimal() +
  labs(
    title = "ARIMA / ETS / XGBoost Recursive Forecast",
    x = "年月",
    y = "申請總金額",
    color = "資料類型"
  )

#Hybrid Modelling phase
#Parameters

bt_eval_branch <- backtest_all %>%
  group_by(據點代號, model) %>%
  summarise(
    RMSE = sqrt(mean((actual - pred)^2, na.rm = TRUE)),
    MAE  = mean(abs(actual - pred), na.rm = TRUE),
    MAPE = mean(abs((actual - pred) / actual), na.rm = TRUE) * 100,
    .groups = "drop"
  )

print(bt_eval_branch)

bt_weights_branch <- bt_eval_branch %>%
  mutate(inv_rmse = 1 / RMSE) %>%
  group_by(據點代號) %>%
  mutate(weight = inv_rmse / sum(inv_rmse, na.rm = TRUE)) %>%
  ungroup()

print(bt_weights_branch)

forecast_all <- bind_rows(
  arima_forecast %>% select(年月, 據點代號, model, pred),
  ets_forecast   %>% select(年月, 據點代號, model, pred),
  xgb_forecast   %>% select(年月, 據點代號, model, pred)
)

hybrid_forecast_branch <- forecast_all %>%
  left_join(
    bt_weights_branch %>% select(據點代號, model, weight),
    by = c("據點代號", "model")
  ) %>%
  mutate(weighted_pred = pred * weight) %>%
  group_by(年月, 據點代號) %>%
  summarise(
    pred = sum(weighted_pred, na.rm = TRUE),
    model = "Hybrid",
    .groups = "drop"
  )

print(hybrid_forecast_branch)

forecast_all_with_hybrid <- bind_rows(
  forecast_all,
  hybrid_forecast_branch
)

history_plot_df <- model_df_final %>%
  filter(據點代號 %in% c("B01", "B02", "B03", "B04", "B05")) %>%
  select(年月, 據點代號, 申請總金額) %>%
  mutate(type = "歷史", value = 申請總金額) %>%
  select(年月, 據點代號, type, value)

forecast_plot_df <- forecast_all_with_hybrid %>%
  mutate(type = model, value = pred) %>%
  select(年月, 據點代號, type, value)

plot_df <- bind_rows(history_plot_df, forecast_plot_df)

ggplot(plot_df, aes(x = 年月, y = value, color = type)) +
  geom_line(linewidth = 0.9) +
  facet_wrap(~ 據點代號, scales = "free_y") +
  theme_minimal(base_size = 14) +
  labs(
    title = "ARIMA / ETS / XGBoost / Hybrid Forecast",
    x = "年月",
    y = "申請總金額",
    color = "資料類型"
  )

#Model Charateristics divide
forecast_all_h <- forecast_all %>%
  arrange(據點代號, 年月) %>%
  group_by(據點代號) %>%
  mutate(h = row_number()) %>%   # h = 第幾期（1,2,3,...）
  ungroup()

hybrid_horizon <- forecast_all_h %>%
  group_by(據點代號, 年月) %>%
  summarise(
    pred = case_when(

      # 🔥 t+1：完全用 XGB
      first(h) == 1 ~ pred[model == "XGB_recursive"],

      # 🔥 t+2：三模型平均
      first(h) == 2 ~ mean(pred, na.rm = TRUE),

      # 🔥 t+3+：只用 ARIMA + ETS
      first(h) >= 3 ~ mean(pred[model %in% c("ARIMA", "ETS")], na.rm = TRUE)

    ),
    model = "Hybrid_horizon",
    .groups = "drop"
  )

forecast_all_final <- bind_rows(
  forecast_all,
  hybrid_horizon
)

forecast_plot_df <- forecast_all_final %>%
  mutate(type = model, value = pred) %>%
  select(年月, 據點代號, type, value)

plot_df <- bind_rows(history_plot_df, forecast_plot_df)

ggplot(plot_df, aes(x = 年月, y = value, color = type)) +
  geom_line(linewidth = 0.9) +
  facet_wrap(~ 據點代號, scales = "free_y") +
  theme_minimal(base_size = 14) +
  labs(
    title = "Horizon-based Hybrid Forecast",
    x = "年月",
    y = "申請總金額",
    color = "模型"
  )

#Adaptive Hybrid Forecast Model
branch_list <- c("B01", "B02", "B03", "B04", "B05")
h_max <- 6

#ARIMA
walk_forward_arima_multi <- function(df_branch, target_col = "申請總金額", min_train = 10, h_max = 6) {

  df_branch <- df_branch %>%
    arrange(年月) %>%
    filter(!is.na(.data[[target_col]]))

  n <- nrow(df_branch)
  results <- list()

  for (i in seq(min_train, n - 1)) {

    max_h_here <- min(h_max, n - i)
    if (max_h_here < 1) next

    train_y <- ts(df_branch[[target_col]][1:i], frequency = 12)
    fit <- auto.arima(train_y)
    fc  <- forecast(fit, h = max_h_here)

    for (h in seq_len(max_h_here)) {
      results[[length(results) + 1]] <- tibble(
        年月 = df_branch$年月[i + h],
        actual = df_branch[[target_col]][i + h],
        pred = as.numeric(fc$mean[h]),
        h = h
      )
    }
  }

  bind_rows(results)
}

arima_backtest_h <- model_df_final %>%
  filter(據點代號 %in% branch_list) %>%
  group_split(據點代號) %>%
  map_dfr(function(df_b) {
    branch <- unique(df_b$據點代號)
    walk_forward_arima_multi(df_b, min_train = 10, h_max = h_max) %>%
      mutate(據點代號 = branch, model = "ARIMA")
  })

#ETS
walk_forward_ets_multi <- function(df_branch, target_col = "申請總金額", min_train = 10, h_max = 6) {

  df_branch <- df_branch %>%
    arrange(年月) %>%
    filter(!is.na(.data[[target_col]]))

  n <- nrow(df_branch)
  results <- list()

  for (i in seq(min_train, n - 1)) {

    max_h_here <- min(h_max, n - i)
    if (max_h_here < 1) next

    train_y <- ts(df_branch[[target_col]][1:i], frequency = 12)
    fit <- ets(train_y)
    fc  <- forecast(fit, h = max_h_here)

    for (h in seq_len(max_h_here)) {
      results[[length(results) + 1]] <- tibble(
        年月 = df_branch$年月[i + h],
        actual = df_branch[[target_col]][i + h],
        pred = as.numeric(fc$mean[h]),
        h = h
      )
    }
  }

  bind_rows(results)
}

ets_backtest_h <- model_df_final %>%
  filter(據點代號 %in% branch_list) %>%
  group_split(據點代號) %>%
  map_dfr(function(df_b) {
    branch <- unique(df_b$據點代號)
    walk_forward_ets_multi(df_b, min_train = 24, h_max = h_max) %>%
      mutate(據點代號 = branch, model = "ETS")
  })

#XGBoost
walk_forward_xgb_multi <- function(df_branch,
                                   feature_cols,
                                   target_col = "申請總金額",
                                   min_train = 10,
                                   h_max = 6) {

  df_branch <- df_branch %>%
    arrange(年月)

  n <- nrow(df_branch)
  results <- list()

  for (i in seq(min_train, n - 1)) {

    train_df <- df_branch[1:i, ] %>%
      filter(if_all(all_of(feature_cols), ~ !is.na(.x))) %>%
      filter(!is.na(.data[[target_col]]))

    if (nrow(train_df) < 12) next

    fit <- xgb.train(
      params = list(
        objective = "reg:squarederror",
        eval_metric = "rmse",
        eta = 0.05,
        max_depth = 4,
        min_child_weight = 3,
        subsample = 0.8,
        colsample_bytree = 0.8
      ),
      data = xgb.DMatrix(
        data = as.matrix(train_df[, feature_cols]),
        label = train_df[[target_col]]
      ),
      nrounds = 200,
      verbose = 0
    )

    history_vals <- df_branch[[target_col]][1:i]
    last_date <- df_branch$年月[i]
    max_h_here <- min(h_max, n - i)

    for (h in seq_len(max_h_here)) {
      future_date <- last_date %m+% months(h)

      new_row <- tibble(
        年月 = future_date,
        month = month(future_date),
        quarter = quarter(future_date),
        year = year(future_date),

        lag1_申請總金額 = tail(history_vals, 1),
        lag2_申請總金額 = tail(history_vals, 2)[1],
        lag3_申請總金額 = tail(history_vals, 3)[1],
        lag6_申請總金額 = tail(history_vals, 6)[1],

        rolling3_申請總金額 = mean(tail(history_vals, 3), na.rm = TRUE),
        rolling6_申請總金額 = mean(tail(history_vals, 6), na.rm = TRUE),

        trend_3m = tail(history_vals, 1) - tail(history_vals, 3)[1],
        trend_6m = tail(history_vals, 1) - tail(history_vals, 6)[1],

        growth_1m = ifelse(
          tail(history_vals, 2)[1] != 0,
          (tail(history_vals, 1) - tail(history_vals, 2)[1]) / tail(history_vals, 2)[1],
          NA_real_
        ),

        growth_3m = ifelse(
          tail(history_vals, 3)[1] != 0,
          (tail(history_vals, 1) - tail(history_vals, 3)[1]) / tail(history_vals, 3)[1],
          NA_real_
        ),

        volatility_3m = sd(tail(history_vals, 3), na.rm = TRUE),
        volatility_6m = sd(tail(history_vals, 6), na.rm = TRUE),

        sin_month = sin(2 * pi * month(future_date) / 12),
        cos_month = cos(2 * pi * month(future_date) / 12)
      )

      pred <- predict(
        fit,
        xgb.DMatrix(data = as.matrix(new_row[, feature_cols]))
      )

      history_vals <- c(history_vals, pred)

      results[[length(results) + 1]] <- tibble(
        年月 = df_branch$年月[i + h],
        actual = df_branch[[target_col]][i + h],
        pred = as.numeric(pred),
        h = h
      )
    }
  }

  bind_rows(results)
}

xgb_backtest_h <- model_df_recursive %>%
  filter(據點代號 %in% branch_list) %>%
  group_split(據點代號) %>%
  map_dfr(function(df_b) {
    branch <- unique(df_b$據點代號)
    walk_forward_xgb_multi(
      df_b,
      feature_cols = feature_cols_recursive_safe,
      min_train = 24,
      h_max = h_max
    ) %>%
      mutate(據點代號 = branch, model = "XGB")
  })

#Combine
backtest_all_h <- bind_rows(
  arima_backtest_h,
  ets_backtest_h,
  xgb_backtest_h
)
bt_eval_h <- backtest_all_h %>%
  group_by(據點代號, model, h) %>%
  summarise(
    RMSE = sqrt(mean((actual - pred)^2, na.rm = TRUE)),
    MAE  = mean(abs(actual - pred), na.rm = TRUE),
    MAPE = mean(abs((actual - pred) / actual), na.rm = TRUE) * 100,
    .groups = "drop"
  )

bt_weights_h <- bt_eval_h %>%
  mutate(inv_rmse = 1 / RMSE) %>%
  group_by(據點代號, h) %>%
  mutate(weight = inv_rmse / sum(inv_rmse, na.rm = TRUE)) %>%
  ungroup()

forecast_all <- bind_rows(
  arima_forecast %>% select(年月, 據點代號, model, pred),
  ets_forecast   %>% select(年月, 據點代號, model, pred),
  xgb_forecast   %>% select(年月, 據點代號, model, pred)
)

forecast_all_h <- forecast_all %>%
  arrange(據點代號, model, 年月) %>%
  group_by(據點代號, model) %>%
  mutate(h = row_number()) %>%
  ungroup()

hybrid_auto <- forecast_all_h %>%
  left_join(
    bt_weights_h %>%
      select(據點代號, h, model, weight_h = weight),
    by = c("據點代號", "h", "model")
  ) %>%
  left_join(
    bt_weights_branch %>%
      select(據點代號, model, weight_branch = weight),
    by = c("據點代號", "model")
  ) %>%
  left_join(
    bt_eval_h %>%
      select(據點代號, model, h, RMSE),
    by = c("據點代號", "model", "h")
  ) %>%
  mutate(
    weight_final = coalesce(weight_h, weight_branch)
  ) %>%
  group_by(據點代號, h) %>%
  mutate(
    weight_final = weight_final / sum(weight_final, na.rm = TRUE)
  ) %>%
  ungroup() %>%
  mutate(
    weighted_pred = pred * weight_final,
    weighted_var  = (weight_final^2) * (RMSE^2)
  ) %>%
  group_by(據點代號, 年月, h) %>%
  summarise(
    pred = sum(weighted_pred, na.rm = TRUE),
    hybrid_sd = sqrt(sum(weighted_var, na.rm = TRUE)),
    lower95 = pred - 1.96 * hybrid_sd,
    upper95 = pred + 1.96 * hybrid_sd,
    model = "Hybrid_auto",
    .groups = "drop"
  )

history_plot_df <- model_df_final %>%
  filter(據點代號 %in% branch_list) %>%
  select(年月, 據點代號, 申請總金額) %>%
  mutate(
    type = "歷史",
    value = 申請總金額,
    lower95 = NA_real_,
    upper95 = NA_real_
  ) %>%
  select(年月, 據點代號, type, value, lower95, upper95)

forecast_plot_df <- bind_rows(
  forecast_all %>%
    mutate(
      type = model,
      value = pred,
      lower95 = NA_real_,
      upper95 = NA_real_
    ) %>%
    select(年月, 據點代號, type, value, lower95, upper95),

  hybrid_auto %>%
    mutate(
      type = model,
      value = pred
    ) %>%
    select(年月, 據點代號, type, value, lower95, upper95)
)

plot_df <- bind_rows(history_plot_df, forecast_plot_df)

ggplot(plot_df, aes(x = 年月, y = value, color = type)) +
  geom_line(linewidth = 0.9) +
  facet_wrap(~ 據點代號, scales = "free_y") +
  theme_minimal(base_size = 14) +
  labs(
    title = "Auto-horizon Hybrid Forecast",
    x = "年月",
    y = "申請總金額",
    color = "模型"
  )

branch_list <- c("B01", "B02", "B03", "B04", "B05")

make_branch_plotly <- function(df_branch) {

  branch <- unique(df_branch$據點代號)
  model_levels <- c("歷史", "ARIMA", "ETS", "XGB_recursive", "Hybrid_auto")

  df_branch <- df_branch %>%
    mutate(
      type = factor(type, levels = model_levels)
    ) %>%
    arrange(type, 年月)

  p <- plot_ly()

  # 先全部加進去
  for (i in seq_along(model_levels)) {
    m <- model_levels[i]
    df_m <- df_branch %>% filter(type == m)

    p <- p %>%
      add_lines(
        data = df_m,
        x = ~年月,
        y = ~value,
        name = m,
        visible = if (m == "Hybrid_auto") TRUE else if (m == "歷史") TRUE else FALSE,
        hovertemplate = paste0(
          "據點: ", branch,
          "<br>模型: ", m,
          "<br>年月: %{x}",
          "<br>金額: %{y:,.0f}<extra></extra>"
        )
      )

    if (m == "Hybrid_auto") {
      p <- p %>%
        add_ribbons(
          data = df_m,
          x = ~年月,
          ymin = ~lower95,
          ymax = ~upper95,
          name = "Hybrid 95% CI",
          line = list(color = "transparent"),
          fillcolor = "rgba(0, 100, 255, 0.15)",
          showlegend = TRUE,
          visible = TRUE
        )
    }
  }

  # 下拉選單
  buttons <- list(
    list(
      method = "update",
      args = list(
        list(visible = c(TRUE, FALSE, FALSE, FALSE, FALSE)),
        list(title = paste0(branch, " 預測圖：歷史"))
      ),
      label = "歷史"
    ),
    list(
      method = "update",
      args = list(
        list(visible = c(TRUE, TRUE, FALSE, FALSE, FALSE)),
        list(title = paste0(branch, " 預測圖：歷史 + ARIMA"))
      ),
      label = "ARIMA"
    ),
    list(
      method = "update",
      args = list(
        list(visible = c(TRUE, FALSE, TRUE, FALSE, FALSE)),
        list(title = paste0(branch, " 預測圖：歷史 + ETS"))
      ),
      label = "ETS"
    ),
    list(
      method = "update",
      args = list(
        list(visible = c(TRUE, FALSE, FALSE, TRUE, FALSE)),
        list(title = paste0(branch, " 預測圖：歷史 + XGB"))
      ),
      label = "XGB"
    ),
    list(
      method = "update",
      args = list(
        list(visible = c(TRUE, FALSE, FALSE, FALSE, TRUE)),
        list(title = paste0(branch, " 預測圖：歷史 + Hybrid"))
      ),
      label = "Hybrid"
    ),
    list(
      method = "update",
      args = list(
        list(visible = c(TRUE, TRUE, TRUE, TRUE, TRUE)),
        list(title = paste0(branch, " 預測圖：全部模型"))
      ),
      label = "全部"
    )
  )

  p <- p %>%
    layout(
      title = paste0(branch, " 預測圖：歷史 + Hybrid"),
      xaxis = list(title = "年月"),
      yaxis = list(title = "申請總金額"),
      updatemenus = list(
        list(
          type = "dropdown",
          active = 4,
          buttons = buttons,
          x = 1.05,
          y = 1
        )
      ),
      legend = list(orientation = "h", x = 0, y = -0.2)
    )

  return(p)
}
plotly_list <- plot_df %>%
  filter(據點代號 %in% branch_list) %>%
  group_split(據點代號) %>%
  setNames(branch_list) %>%
  map(make_branch_plotly)
plotly_list[["B01"]]
plotly_list[["B02"]]
plotly_list[["B03"]]
plotly_list[["B04"]]
plotly_list[["B05"]]

output_dir <- Sys.getenv("REPORT_OUTPUT_DIR", "outputs")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

writexl::write_xlsx(
  hybrid_auto,
  path = file.path(output_dir, "hybrid_forecast.xlsx")
)
