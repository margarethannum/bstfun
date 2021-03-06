#' Create a cross table of summary statistics
#'
#' \Sexpr[results=rd, stage=render]{lifecycle::badge("experimental")}
#' Wrapper for [tbl_summary] to cross tabulate two variables
#'
#' @param data A data frame
#' @param row A column name (quoted or unquoted) in data to be used for columns
#' of cross table.
#' @param col A column name (quoted or unquoted) in data to be used for rows
#' of cross table.
#' @param statistic A string with the statistic name in curly brackets to
#' be replaced with the numeric statistic (see glue::glue).
#' The default is `{n}`. If percent argument is `"column"`, `"row"`, or `"cell"`,
#' default is `{n} ({p}%)`.
#' @inheritParams gtsummary::add_p
#' @inheritParams gtsummary::tbl_summary
#' @param add_p Logical value indicating whether to add p-value to compare
#' `col` and `row` variables. Default is `FALSE`.
#' @param test A string specifying statistical test to perform. Default is
#' "`chisq.test`" when expected cell counts >=5 and and "`fisher.test`" when
#' expected cell counts <5.
#'
#' @author Karissa Whiting
#' @export
#' @return A `tbl_cross` object
#' @examples
#' tbl_cross_ex1 <-
#'   trial[c("response", "trt")] %>%
#'   tbl_cross(row = trt, col = response)
#'
#' @section Example Output:
#' \if{html}{\figure{tbl_cross_ex.png}{options: width=50\%}}

tbl_cross <- function(data,
                      row = NULL,
                      col = NULL,
                      label = NULL,
                      statistic = NULL,
                      percent = c("none", "column", "row", "cell"),
                      missing = c("ifany", "always", "no"),
                      missing_text = "Unknown",
                      add_p = FALSE,
                      test = NULL,
                      pvalue_fun = function(x) style_pvalue(x, prepend_p = TRUE)) {
  # checking data input --------------------------------------------------------
  if (!is.data.frame(data) || nrow(data) == 0 || ncol(data) < 2) {
    stop("`data=` argument must be a data frame with at least one row and two columns.",
         call. = FALSE)
  }

  # converting inputs to string ------------------------------------------------
  row <- gtsummary:::var_input_to_string(
    data = data, select_input = !!rlang::enquo(row),
    arg_name = "row", select_single = TRUE
  )

  col <- gtsummary:::var_input_to_string(
    data = data, select_input = !!rlang::enquo(col),
    arg_name = "col", select_single = TRUE
  )

  # matching arguments ---------------------------------------------------------
  missing <- match.arg(missing)
  percent <- match.arg(percent)

  # saving function intputs
  tbl_cross_inputs <- as.list(environment())

  # if no col AND no row provided, default to first two columns of data --------
  if (is.null(row) && is.null(col)) {
    row <- names(data)[1]
    col <- names(data)[2]
  }

  # if only one of col/row provided, error
  if(sum(is.null(row), is.null(col)) == 1) {
    stop("Please specify which columns to use for both `col=` and `row=` arguments",
         call. = FALSE)
  }
  if ("..total.." %in% c(row, col)) {
    stop("Arguments `row=` and `col=` cannot be named '..total..'", call. = FALSE)
  }

  # create new dummy col for tabulating column totals in cross table
  data <- data %>%
    select(one_of(row, col)) %>%
    mutate(..total.. = 1)

  # get labels -----------------------------------------------------------------
  label <- gtsummary:::tidyselect_to_list(data, label)
  new_label <-  list()

  new_label[[row]] <- label[[row]] %||% attr(data[[row]], "label") %||% row
  new_label[[col]] <- label[[col]] %||% attr(data[[col]], "label") %||% col
  new_label[["..total.."]] <- "Total"

  # statistic argument ---------------------------------------------------------
  # if no user-defined stat, default to {n} if percent is "none"
  statistic <- statistic %||% ifelse(percent == "none", "{n}", "{n} ({p}%)")
  if (!rlang::is_string(statistic)) {
    stop("`statistic=` argument must be a string of length one.", call. = FALSE)
  }

  # omit missing data, or factorize missing level ------------------------------
  data <- data %>%
    mutate_at(vars(row, col), as.factor) %>%
    mutate_at(
      vars(row, col),
      ~ switch(
        missing,
        "no" = .,
        "ifany" = forcats::fct_explicit_na(., missing_text),
        "always" = forcats::fct_explicit_na(., missing_text) %>%
          forcats::fct_expand(missing_text)
      )
    )

  if (missing == "no") {
    n_missing <- !stats::complete.cases(data) %>% sum()
    data <- stats::na.omit(data)

    message(glue("{n_missing} observations with missing data have been removed."))
  }

  # create main table ----------------------------------------------------------
  x <- data %>%
    select(one_of(row, col, "..total..")) %>%
    gtsummary::tbl_summary(
      by = col,
      statistic = stats::as.formula(glue("everything() ~ '{statistic}'")),
      percent = switch(percent != "none", percent),
      label = new_label,
      missing_text = missing_text
    ) %>%
    gtsummary::add_overall(last = TRUE) %>%
    gtsummary::bold_labels() %>%
    gtsummary::modify_header(
      stat_by = "{level}",
      stat_0 = " "
    )

  # get text for gt source note
  stat_source_note_text <- gtsummary:::footnote_stat_label(x$meta_data)

  # calculate and format p-value for source note as needed --------------------
  p_value = vector("character", length=0)

  if(add_p == TRUE || !is.null(test)) {
    # adding test name if supplied (NULL otherwise)
    input_test <- switch(!is.null(test),
                         stats::as.formula(glue("everything() ~ '{test}'")))
    # running add_p to add thep-value to the output
    x <- gtsummary::add_p(x, include = c(row, col), test = input_test)

    x$table_header <- x$table_header %>%
      mutate(
        hide = case_when(
          column == "p.value" ~ TRUE,
          TRUE ~ hide
        )
      )

    # formatting p-value, and grabbing test name from footnote
    p_value <-  x$table_body$p.value[!is.na(x$table_body$p.value)] %>%
      pvalue_fun()
    p_val_source_note_text <- x$table_header %>%
      filter(.data$column == "p.value") %>%
      pull(.data$footnote)
  }

  # clear existing tbl_summary footnote
  x$table_header$footnote <- list(NULL)
  x <- gtsummary:::update_calls_from_table_header(x)

  # update inputs and call list in return
  x[["call_list"]] <- list(tbl_cross = match.call())
  x[["inputs"]] <- tbl_cross_inputs

  class(x) <- c("tbl_cross", "tbl_summary", "gtsummary")

  # gt function calls ----------------------------------------------------------
  # quoting returns an expression to be evaluated later
  x$gt_calls[["tab_spanner"]] <-
    glue(
      "gt::tab_spanner(",
      "label = gt::md('**{new_label[[col]]}**'), ",
      "columns = contains('stat_')) %>%",
      "gt::tab_spanner(label = gt::md('**Total**'), ",
      "columns = vars(stat_0))"
    )

  x$gt_calls[["tab_source_note"]] <-
    ifelse(
      length(p_value) > 0,
      glue("gt::tab_source_note(source_note = '{stat_source_note_text}') %>%",
           "gt::tab_source_note(source_note =
              glue::glue('{p_val_source_note_text}', ', ',
             '{p_value}'))"),
      glue("gt::tab_source_note(source_note = '{stat_source_note_text}')"))

  # returning results ----------------------------------------------------------
  x
}

