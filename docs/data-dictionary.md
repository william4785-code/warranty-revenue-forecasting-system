# Public Data Dictionary

## Required monthly input

| Column | Type | Required | Definition |
|---|---|---:|---|
| `date` | Date | Yes | First day of a completed calendar month |
| `branch_id` | Character | Yes | Stable anonymized branch key |
| `revenue` | Numeric | Yes | Monthly warranty revenue target |

The combination of `date` and `branch_id` must be unique.

## Optional synthetic demonstration fields

| Column | Type | Definition |
|---|---|---|
| `claim_count` | Integer | Synthetic monthly case count |
| `category_a_count` | Integer | Synthetic category A count |
| `category_b_count` | Integer | Synthetic category B count |

These fields demonstrate a possible public schema but are not used in the
current production feature routes.

## Application-level input

| Column | Type | Description |
|---|---|---|
| `application_id` | character | Synthetic or irreversibly anonymized unique record key |
| `branch_id` | character | Public operating-unit alias |
| `application_date` | Date | Date the application entered the progress curve |
| `amount` | numeric | Non-negative synthetic or sanitized amount |

## Nowcast output

| Column | Description |
|---|---|
| `cutoff_day` | Latest validated cutoff not later than the analysis date |
| `cumulative_amount` | Amount observed through the cutoff |
| `baseline_pred` | Original Hybrid h=1 forecast |
| `curve_pred` | Progress-curve estimate |
| `curve_weight` | Prior-history-selected curve contribution |
| `pred` | Final open-month estimate |
| `nowcast_status` | Blend or explicit fallback reason |

The public repository does not contain real application IDs, actual revenue,
internal category fields, or branch mappings.

## Backtest output

| Column | Definition |
|---|---|
| `origin` | Last historical month available to the forecast |
| `date` | Predicted month |
| `branch_id` | Anonymized branch |
| `h` | Forecast horizon |
| `model` | `ARIMA`, `ETS`, `XGB`, or `Hybrid` |
| `actual` | Historical observed value |
| `pred` | Point forecast |
| `weight_source` | Evidence level used by Hybrid |

## Final forecast output

| Column | Definition |
|---|---|
| `pred` | Hybrid point forecast |
| `lower95` | Approximate lower 95% bound, floored at zero |
| `upper95` | Approximate upper 95% bound |
| `hybrid_rmse` | Residual scale used for the interval |
| `interval_source` | Branch-horizon or branch fallback |
| `weight_source` | Branch-horizon or branch weight source |

## Privacy requirements

Public demonstrations must not contain:

- real branch IDs or mappings;
- actual warranty revenue;
- customer or claim-level records;
- internal database/table names;
- company-specific output paths.
