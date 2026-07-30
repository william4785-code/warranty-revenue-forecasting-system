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
