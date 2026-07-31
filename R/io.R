load_monthly_csv <- function(path) {
  if (!file.exists(path)) {
    stop("Input CSV does not exist: ", path, call. = FALSE)
  }

  data <- utils::read.csv(path, stringsAsFactors = FALSE)
  data$date <- as.Date(data$date)
  data$branch_id <- as.character(data$branch_id)
  data$revenue <- as.numeric(data$revenue)
  assert_monthly_schema(data)
  data
}

load_monthly_mariadb <- function() {
  required <- c(
    "MARIADB_USER", "MARIADB_PASSWORD",
    "MARIADB_DATABASE", "MARIADB_MONTHLY_TABLE"
  )
  missing <- required[!nzchar(Sys.getenv(required))]
  if (length(missing) > 0L) {
    stop(
      "Missing MariaDB environment variables: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  table_name <- Sys.getenv("MARIADB_MONTHLY_TABLE")
  if (!grepl("^[A-Za-z0-9_]+$", table_name)) {
    stop("Invalid MariaDB table name.", call. = FALSE)
  }

  con <- DBI::dbConnect(
    RMariaDB::MariaDB(),
    host = Sys.getenv("MARIADB_HOST", "127.0.0.1"),
    port = as.integer(Sys.getenv("MARIADB_PORT", "3306")),
    user = Sys.getenv("MARIADB_USER"),
    password = Sys.getenv("MARIADB_PASSWORD"),
    dbname = Sys.getenv("MARIADB_DATABASE")
  )
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  data <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT date, branch_id, revenue FROM `%s`",
      table_name
    )
  )
  data$date <- as.Date(data$date)
  assert_monthly_schema(data)
  data
}

load_portfolio_input <- function() {
  input_csv <- Sys.getenv("INPUT_CSV")
  if (nzchar(input_csv)) {
    return(load_monthly_csv(input_csv))
  }
  load_monthly_mariadb()
}
