# Leakage-safe Champion / Challenger validation -----------------------------

rmse_value <- function(actual, pred) {
  sqrt(mean((actual - pred)^2))
}

relative_rmse_change <- function(control, challenger) {
  if (!is.finite(control) || control <= 0 || !is.finite(challenger)) {
    return(NA_real_)
  }
  (challenger / control - 1) * 100
}

chronological_origin_split <- function(origins, development_fraction = 0.5) {
  origins <- sort(unique(as.Date(origins)))
  if (length(origins) < 4L) {
    stop("At least four forecast origins are required.", call. = FALSE)
  }
  development_n <- max(2L, floor(length(origins) * development_fraction))
  development_n <- min(development_n, length(origins) - 2L)
  development <- origins[seq_len(development_n)]
  test <- origins[(development_n + 1L):length(origins)]
  if (max(development) >= min(test)) {
    stop("Development origins must precede test origins.", call. = FALSE)
  }
  list(development = development, test = test)
}

compare_prediction_sets <- function(
    control,
    challenger,
    keys = c("branch_id", "origin", "date", "h")) {
  control_common <- control |>
    dplyr::select(dplyr::all_of(keys), actual_control = "actual", control = "pred")
  challenger_common <- challenger |>
    dplyr::select(
      dplyr::all_of(keys),
      actual_challenger = "actual",
      challenger = "pred"
    )
  common <- dplyr::inner_join(control_common, challenger_common, by = keys)
  if (nrow(common) != nrow(control) || nrow(common) != nrow(challenger)) {
    stop("Champion and Challenger do not share identical evaluation keys.", call. = FALSE)
  }
  if (any(abs(common$actual_control - common$actual_challenger) > 1e-8)) {
    stop("Champion and Challenger actuals do not reconcile.", call. = FALSE)
  }
  common |>
    dplyr::rename(actual = "actual_control") |>
    dplyr::select(-"actual_challenger")
}

comparison_summary <- function(common) {
  control_rmse <- rmse_value(common$actual, common$control)
  challenger_rmse <- rmse_value(common$actual, common$challenger)
  tibble::tibble(
    n = nrow(common),
    control_rmse = control_rmse,
    challenger_rmse = challenger_rmse,
    rmse_change_pct = relative_rmse_change(control_rmse, challenger_rmse)
  )
}

promotion_gate_table <- function(
    xgb_change_pct,
    hybrid_change_pct,
    improved_horizon_n,
    branch_changes_pct,
    nowcast_changes_pct = numeric(),
    fallback_unchanged = TRUE,
    branch_guardrail = 5) {
  nowcast_available <- length(nowcast_changes_pct) > 0L
  gates <- tibble::tibble(
    gate = c(
      "xgb_overall_improves",
      "at_least_four_horizons_improve",
      "hybrid_overall_improves",
      "all_nowcast_cutoffs_improve",
      "no_branch_material_degradation",
      "short_history_fallback_unchanged"
    ),
    passed = c(
      is.finite(xgb_change_pct) && xgb_change_pct < 0,
      improved_horizon_n >= 4L,
      is.finite(hybrid_change_pct) && hybrid_change_pct < 0,
      if (nowcast_available) all(nowcast_changes_pct < 0) else NA,
      all(branch_changes_pct <= branch_guardrail),
      isTRUE(fallback_unchanged)
    ),
    evidence_available = c(TRUE, TRUE, TRUE, nowcast_available, TRUE, TRUE)
  )
  decision <- if (all(gates$passed[gates$evidence_available])) {
    "PROMOTION_CANDIDATE"
  } else {
    "RETAIN_CHAMPION"
  }
  list(decision = decision, gates = gates)
}

replace_xgb_backtest <- function(control_backtest, challenger_backtest) {
  challenger_xgb <- dplyr::filter(challenger_backtest, .data$model == "XGB")
  control_non_xgb <- dplyr::filter(control_backtest, .data$model != "XGB")
  output <- dplyr::bind_rows(control_non_xgb, challenger_xgb)
  assert_backtest_common_keys(output)
  output
}

with_xgb_candidate <- function(config, specification) {
  output <- config
  for (name in names(specification$params)) {
    output$xgb_params[[name]] <- specification$params[[name]]
  }
  output$nrounds <- as.integer(specification$nrounds)
  output
}

run_fixed_challenger_holdout <- function(
    monthly_data,
    candidate_specs,
    control_config = portfolio_config(),
    n_origins = 8L,
    branch_guardrail = 5) {
  if (length(candidate_specs) == 0L) {
    stop("At least one Challenger specification is required.", call. = FALSE)
  }
  candidate_ids <- names(candidate_specs)
  if (is.null(candidate_ids)) candidate_ids <- rep("", length(candidate_specs))
  candidate_ids <- vapply(seq_along(candidate_specs), function(i) {
    if (nzchar(candidate_ids[[i]])) candidate_ids[[i]] else {
      sprintf("candidate_%02d", i)
    }
  }, character(1L))
  control_backtest <- walk_forward_backtest(
    monthly_data,
    config = control_config,
    n_origins = n_origins
  )
  split <- chronological_origin_split(control_backtest$origin)
  candidate_backtests <- vector("list", length(candidate_specs))
  development_scores <- vector("list", length(candidate_specs))

  for (i in seq_along(candidate_specs)) {
    specification <- candidate_specs[[i]]
    candidate_id <- candidate_ids[[i]]
    candidate_config <- with_xgb_candidate(control_config, specification)
    candidate_backtests[[i]] <- walk_forward_backtest(
      monthly_data,
      config = candidate_config,
      n_origins = n_origins
    )
    common <- compare_prediction_sets(
      dplyr::filter(
        control_backtest,
        .data$model == "XGB",
        .data$origin %in% split$development
      ),
      dplyr::filter(
        candidate_backtests[[i]],
        .data$model == "XGB",
        .data$origin %in% split$development
      )
    )
    development_scores[[i]] <- comparison_summary(common) |>
      dplyr::mutate(candidate_id = candidate_id, .before = 1L)
  }
  scores <- dplyr::bind_rows(development_scores) |>
    dplyr::arrange(.data$challenger_rmse, .data$candidate_id)
  selected_id <- scores$candidate_id[[1L]]
  selected_index <- match(selected_id, candidate_ids)
  selected_backtest <- candidate_backtests[[selected_index]]

  control_test <- dplyr::filter(
    control_backtest,
    .data$model == "XGB",
    .data$origin %in% split$test
  )
  challenger_test <- dplyr::filter(
    selected_backtest,
    .data$model == "XGB",
    .data$origin %in% split$test
  )
  xgb_common <- compare_prediction_sets(control_test, challenger_test)
  xgb_summary <- comparison_summary(xgb_common)
  by_h <- xgb_common |>
    dplyr::group_by(.data$h) |>
    dplyr::group_modify(~ comparison_summary(.x)) |>
    dplyr::ungroup()
  by_branch <- xgb_common |>
    dplyr::group_by(.data$branch_id) |>
    dplyr::group_modify(~ comparison_summary(.x)) |>
    dplyr::ungroup()

  challenger_components <- replace_xgb_backtest(
    control_backtest,
    selected_backtest
  )
  control_hybrid <- build_hybrid_backtest(control_backtest)
  challenger_hybrid <- build_hybrid_backtest(challenger_components)
  hybrid_common <- compare_prediction_sets(
    dplyr::filter(control_hybrid, .data$origin %in% split$test),
    dplyr::filter(challenger_hybrid, .data$origin %in% split$test)
  )
  hybrid_summary <- comparison_summary(hybrid_common)
  gates <- promotion_gate_table(
    xgb_change_pct = xgb_summary$rmse_change_pct[[1L]],
    hybrid_change_pct = hybrid_summary$rmse_change_pct[[1L]],
    improved_horizon_n = sum(by_h$rmse_change_pct < 0),
    branch_changes_pct = by_branch$rmse_change_pct,
    fallback_unchanged = TRUE,
    branch_guardrail = branch_guardrail
  )

  list(
    decision = gates$decision,
    selected_candidate = selected_id,
    development_origins = split$development,
    test_origins = split$test,
    development_scores = scores,
    xgb_summary = xgb_summary,
    xgb_by_h = by_h,
    xgb_by_branch = by_branch,
    hybrid_summary = hybrid_summary,
    promotion_gates = gates$gates
  )
}
