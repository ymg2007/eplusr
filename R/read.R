################################################################################
#                          EnergyPlus Results Reading                          #
################################################################################

#' Import EnergyPlus .epg group file
#'
#' \code{import_epg} returns a tibble which contains the necessary infomation in
#' order to run simulations using \code{\link{run_epg}}.
#'
#' @param epg A file path of EnergyPlus .epg file.
#' @return A tibble.
#' @importFrom readr read_csv cols col_integer
#' @importFrom dplyr as_tibble mutate select one_of
#' @importFrom purrr map_at
#' @export
# import_epg{{{1
import_epg <- function(epg){

    sim_info <- readr::read_csv(file = epg, comment = "!",
                                col_names = c("model", "weather", "result", "run_times"),
                                col_types = cols(.default = "c", run_times = col_integer()))

    sim_info <- dplyr::as_tibble(purrr::map_at(sim_info,
                                               c("model", "weather", "result"),
                                               normalizePath,  winslash = "/", mustWork = FALSE
                                               ))
    sim_info <- dplyr::mutate(sim_info, output_dir = dirname(result))
    sim_info <- dplyr::mutate(sim_info, output_prefix = basename(result))
    sim_info <- dplyr::select(sim_info, dplyr::one_of("model", "weather", "output_dir", "output_prefix", "run_times"))

    attr(sim_info, "job_type") <- "epg"

    return(sim_info)
}
# }}}1

#' Import jEPlus .json type project.
#'
#' \code{import_jeplus} takes a file path of an .json type project of jEPlus,
#' and return a list containing model paths, weather paths, parametric fields,
#' and parametric values. The returned list will have an attribute 'job_type'
#' with value 'jeplus' which will be used when running jobs using
#' \link{\code{run_job}}.
#'
#' @param json A file path of a .json file.
#' @return A list containing project info.
#' @importFrom jsonlite fromJSON
#' @importFrom stringr str_split str_replace_all str_replace str_detect str_replace
#' @importFrom purrr set_names map map_chr map2 set_names flatten_chr cross_n
#' @importFrom data.table rbindlist
#' @importFrom dplyr as_tibble
#' @export
# import_jeplus{{{1
import_jeplus <- function (json) {
    # Read jeplus JSON project file.
    info <- jsonlite::fromJSON(json)

    # Get parameter info.
    params <- info[["parameters"]]

    param_id <- params[["id"]]
    param_name <- params[["name"]]

    param_field <- stringr::str_split(params[["searchString"]], "\\|")
    param_field <- purrr::set_names(param_field, param_name)

    param_value <- stringr::str_replace_all(params[["valuesString"]], "[\\{\\}]", "")
    # Check if  the parametric value is a numeric seq.
    regex_seq <- "\\[(\\d+(?:\\.\\d+)*):(\\d+(?:\\.\\d+)*):(\\d+(?:\\.\\d)*)\\]"
    idx_value_seq <- stringr::str_detect(param_value, regex_seq)

    param_value <- stringr::str_split(param_value, "(\\s)*,(\\s)*")
    param_value <- map2(idx_value_seq, seq_along(param_value),
                        ~{if (.x) {
                             from <- as.numeric(stringr::str_replace(param_value[[.y]], regex_seq, "\\1"))
                             by <- as.numeric(stringr::str_replace(param_value[[.y]], regex_seq, "\\2"))
                             to <- as.numeric(stringr::str_replace(param_value[[.y]], regex_seq, "\\3"))
                             as.character(seq(from = from , to = to, by = by))
                         } else {
                             param_value[[.y]]
                         }})

    # Get selected parameter values.
    param_value_selected <- params[["selectedAltValue"]]
    param_value <- purrr::map2(param_value_selected, param_value, ~{if (.x > 0) .y <- .y[.x] else .y})

    param_value <- purrr::map(param_value, ~stringr::str_split(.x, "(\\s)*\\|(\\s)*"))
    param_value <- purrr::set_names(param_value, param_name)

    # Create case names according to parameter names.
    case_names <- purrr::pmap(list(param_id, param_value, param_value_selected),
                              function(name, value, selected) {
                                  if (as.integer(selected) > 0) {
                                      paste0(name, selected)
                                  } else {
                                      paste0(name, seq_along(value))
                                  }
                              })
    case_names <- dplyr::as_tibble(data.table::rbindlist(purrr::cross_n(case_names)))
    case_names <- map_chr(seq(1:nrow(case_names)), ~paste(case_names[.x,], collapse = "_"))

    # Get all combination of case values.
    param_value <- purrr::cross_n(param_value)
    param_value <- purrr::set_names(param_value, case_names)

    # Get input file info.
    idfs <- purrr::flatten_chr(stringr::str_split(info[["idftemplate"]], "\\s*;\\s*"))
    wthrs <- purrr::flatten_chr(stringr::str_split(info[["weatherFile"]], "\\s*;\\s*"))
    idf_path <- paste0(info[["idfdir"]], idfs)
    wthr_path <- paste0(info[["weatherDir"]], wthrs)

    sim_info <- list(idf_path = idf_path, weather_path = wthr_path,
                     param_field = param_field, param_value = param_value)

    attr(sim_info, "job_type") <- "jeplus"

    return(sim_info)
}
# }}}1

#' Import EPAT .json type project
#'
#' \code{import_epat} takes a file path of an .json type project of EPAT, and
#' return a list containing model paths, weather paths, parametric fields, and
#' parametric values. The returned list will have an attribute 'job_type' with
#' value 'epat' which will be used when running jobs using
#' \link{\code{run_job}}.
#'
#' @param json A file path of a .json file.
#' @return A list containing project info.
#' @importFrom jsonlite fromJSON
#' @importFrom stringr str_split str_replace_all str_replace str_detect str_replace
#' @importFrom purrr set_names map map_chr map2 set_names flatten_chr cross_n
#' @importFrom data.table rbindlist
#' @importFrom dplyr as_tibble
#' @export
# import_epat{{{1
import_epat <- function (json) {
    # Read jeplus JSON project file.
    info <- jsonlite::fromJSON(json)

    # Get parameter info.
    params <- info[["param_table"]]

    param_id <- params[["ID"]]
    param_name <- params[["Name"]]

    param_field <- stringr::str_split(params[["Search Tag"]], "\\|")
    param_field <- purrr::set_names(param_field, param_name)

    param_value <- stringr::str_replace_all(params[["Value Expressions"]], "[\\{\\}]", "")
    # Check if  the parametric value is a numeric seq.
    regex_seq <- "\\[(\\d+(?:\\.\\d+)*):(\\d+(?:\\.\\d+)*):(\\d+(?:\\.\\d)*)\\]"
    idx_value_seq <- stringr::str_detect(param_value, regex_seq)

    param_value <- stringr::str_split(param_value, "(\\s)*,(\\s)*")
    param_value <- map2(idx_value_seq, seq_along(param_value),
                        ~{if (.x) {
                             from <- as.numeric(stringr::str_replace(param_value[[.y]], regex_seq, "\\1"))
                             by <- as.numeric(stringr::str_replace(param_value[[.y]], regex_seq, "\\2"))
                             to <- as.numeric(stringr::str_replace(param_value[[.y]], regex_seq, "\\3"))
                             as.character(seq(from = from , to = to, by = by))
                         } else {
                             param_value[[.y]]
                         }})

    # Get selected parameter values.
    param_value_selected <- as.integer(params[["Fixed Value"]])
    param_value <- purrr::map2(param_value_selected, param_value, ~{if (.x > 0) .y <- .y[.x] else .y})

    param_value <- purrr::map(param_value, ~stringr::str_split(.x, "(\\s)*\\|(\\s)*"))
    param_value <- purrr::set_names(param_value, param_name)

    # Create case names according to parameter names.
    case_names <- purrr::pmap(list(param_id, param_value, param_value_selected),
                              function(name, value, selected) {
                                  if (as.integer(selected) > 0) {
                                      paste0(name, selected)
                                  } else {
                                      paste0(name, seq_along(value))
                                  }
                              })
    case_names <- data.table::rbindlist(purrr::cross_n(case_names))
    case_names <- map_chr(seq(1:nrow(case_names)), ~paste(case_names[.x], collapse = "_"))

    # Get all combination of case values.
    param_value <- purrr::cross_n(param_value)
    param_value <- purrr::set_names(param_value, case_names)

    # Get input file info.
    idf_path <- info[["idf_path"]]
    wthr_path <- info[["weather_path"]]

    # Get other misc info
    eplus_path <- info[["eplus_path"]]
    wd_path <- info[["wd_path"]]
    parallel_num <- info[["parallel_num"]]

    sim_info <- list(idf_path = idf_path, weather_path = wthr_path,
                     param_field = param_field, param_value = param_value,
                     eplus_path = eplus_path, wd_path = wd_path, parallel_num = parallel_num)

    attr(sim_info, "job_type") <- "epat"

    return(sim_info)
}
# }}}1

#' @importFrom tools file_path_sans_ext file_ext
#' @importFrom data.table data.table as.data.table
#' @importFrom dplyr tibble
#' @importFrom purrr map
#' @export
# read_eplus: A function to read EnergyPlus simulation results.
# read_eplus
# {{{1
read_eplus <- function (path, output = c("variable", "meter", "table", "surface report"),
                        year = current_year(), eplus_date_col = "Date/Time",
                        new_date_col = "datetime", tz = Sys.timezone(),
                        rp_na = NA, to_GJ = NULL, unnest = FALSE, long = FALSE) {
    # Check if the input model path is given.
    ext <- tools::file_ext(path)
    if (ext != "") {
        if (length(grep("i[dm]f", ext, ignore.case = TRUE)) == 0) {
            stop("'path' should be a path of folder or a path of the input .idf or .imf file.",
                 call. = FALSE)
        } else {
            prefix = tools::file_path_sans_ext(basename(path))
            file_names <- data.table(prefix = prefix,
                                     variable = paste0(prefix, ".csv"),
                                     meter = paste0(prefix, "Meter.csv"),
                                     surface_report = paste0(prefix, ".eio"),
                                     table = paste0(prefix, "Table.htm"))
            path <- dirname(path)
        }
    } else {
        # Get the output name pattern.
        file_names <- get_eplus_main_output_files(path)
    }

    if (missingArg(output)) {
        stop("Missing 'output', which should be one of c('variable', 'meter', 'table', 'surface report').",
             call. = FALSE)
    }

    if (is.null(to_GJ)) {
        to_GJ <- FALSE
    }

    if (is.na(match(output, c("variable", "meter", "table", "surface report")))) {
        stop("Invalid value of argument 'output'. It should be one of ",
             "c('variable', 'meter', 'table', 'surface report').", call. = FALSE)
    } else if (output == "variable"){
        file_name <- file_names[["variable"]]
    } else if (output == "meter"){
        file_name <- file_names[["meter"]]
    } else if (output == "surface report"){
        file_name <- file_names[["surface_report"]]
    } else {
        file_name <- file_names[["table"]]
    }

    check_eplus_output_file_exist(path, file_names, output)

    if (output == "variable") {
      data <-
          dplyr::tibble(case = file_names[["prefix"]],
                        variable_output = purrr::map(file.path(path, file_name),
                                                     function (file) {
                                                         if (file.exists(file)) {
                                                             read_variable(result = file,
                                                                               year = year,
                                                                               eplus_date_col = eplus_date_col,
                                                                               new_date_col = new_date_col,
                                                                               tz = tz,
                                                                               rp_na = rp_na,
                                                                               long = long)
                                                         } else {
                                                             return(NULL)
                                                         }
                                                     })) #%>% data.table::as.data.table() #%>% tidyr::unnest()

    } else if (output == "meter"){
      data <-
          dplyr::tibble(case = file_names[["prefix"]],
                        meter_output = purrr::map(file.path(path, file_name),
                                                  function (file) {
                                                      if (file.exists(file)) {
                                                          read_variable(result = file,
                                                                            year = year,
                                                                            eplus_date_col = eplus_date_col,
                                                                            new_date_col = new_date_col,
                                                                            tz = tz,
                                                                            to_GJ = to_GJ,
                                                                            rp_na = rp_na,
                                                                            long = long)
                                                      } else {
                                                          return(NULL)
                                                      }
                                                  }
                                                  )) #%>% data.table::as.data.table() #%>% tidyr::unnest()

    } else if (output == "surface report") {
      data <-
          dplyr::tibble(case = file_names[["prefix"]],
                        surface_report = purrr::map(file.path(path, file_name),
                                                    function (file) {
                                                        if (file.exists(file)) {
                                                            read_surf_rpt(eio = file)
                                                        } else {
                                                            return(NULL)
                                                        }
                                                    }
                                                    )) #%>% data.table::as.data.table() #%>% tidyr::unnest()
    } else  {
      data <-
          dplyr::tibble(case = file_names[["prefix"]],
                        table_output = purrr::map(file.path(path, file_name),
                                                  function (file) {
                                                      if (file.exists(file)) {
                                                          read_table(file = file)
                                                      } else {
                                                          return(NULL)
                                                      }
                                                  }
                                                  )) #%>% data.table::as.data.table() #%>% tidyr::unnest()
    }

    if (unnest) {
        data <- tidyr::unnest(data = data)
    }

    return(data)
}
# }}}1

#' @importFrom data.table data.table
# get_eplus_main_output_names
# {{{1
get_eplus_main_output_names <- function (output_prefix, output_pattern) {
    if (all(output_prefix == "in", output_pattern == "legacy")) {
        variable <- "eplusout.csv"
        meter <- "eplusmtr.csv"
        surf_rpt <- "eplusout.eio"
        table <- "eplustbl.csv"
    } else if (all(output_prefix != "in", output_pattern == "capital")) {
        variable <- paste0(output_prefix,  ".csv")
        meter <- paste0(output_prefix, "Meter.csv")
        surf_rpt <- paste0(output_prefix, ".eio")
        table <- paste0(output_prefix, "Table.csv")
    } else {
        stop("Could not detect the result names.")
    }

    main_names <- data.table(prefix = output_prefix,
                             pattern = output_pattern,
                             variable = variable, meter = meter,
                             surface_report = surf_rpt,
                             table = table)

    return(main_names)
}
# }}}1

#' @importFrom purrr map2
#' @importFrom data.table rbindlist
# get_eplus_main_output_files
# {{{1
get_eplus_main_output_files <- function (path) {
    output_prefix <- get_eplus_output_prefix_str(path = path)
    output_pattern <- get_eplus_output_prefix_ptn(output_prefix = output_prefix)
    file_names <- purrr::map2(output_prefix, output_pattern,
                              get_eplus_main_output_names)
    file_names <- data.table::rbindlist(file_names)

    return(file_names)
}
# }}}1

#' @importFrom purrr map
# check_eplus_output_file_exist
# {{{1
check_eplus_output_file_exist <- function (path, file_names, type) {
    input <- file_names[["prefix"]]
    files <- file.path(path, file_names[[type]])
    purrr::map(seq_along(files),
                   function(i) {
                       if (!file.exists(files[i])) {
                           message("EnergyPlus '", type ,"' file '",
                                   basename(files[i]),
                                   "' does not exist for input file '", input[i],
                                   "', and will be ignored during reading process.")
                           return(files[i])
                       } else {
                           return(NULL)
                       }
                   }) %>% unlist
}
# }}}1

#' Read EnergyPlus Surface Details Report from an .eio file.
#'
#' \code{read_surf_rpt} takes a file path of EnergyPlus .eio output file as
#' input, and returns a data.table object which contains the contents of the
#' report. It is worth noting that you have to add an "Output:Surfaces:List"
#' object in your model in order to generate an Surface Details Report in the
#' .eio output file.
#'
#' @param eio A path of an EnergyPlus .eio output file.
#' @return A data.table containing the Surface Details Report.
#' @importFrom stringr str_which str_split str_trim str_replace_all str_replace str_extract
#' @importFrom readr read_lines cols col_character col_double col_integer read_csv
#' @importFrom data.table rbindlist as.data.table fread
#' @importFrom purrr flatten_chr map2
#' @export
# read_surf_rpt
# {{{1
read_surf_rpt <- function(eio){
    # Read raw .eio file
    eio_contents <- readr::read_lines(eio)
    # Row num of all headers
    row_all <- stringr::str_which(eio_contents, "! <.*>")
    # Starting row num of surface details report
    row_surf <- stringr::str_which(eio_contents, "! <Zone/Shading Surfaces>,<Zone Name>/#Shading Surfaces,# Surfaces")
    row_header <- row_surf+1
    row_unit <- row_surf+2

    # Stop if there is no Surface Details Report
    if(length(row_surf) == 0){
        stop("'Surface Details Report' was not found in the eio file. ",
             "Please check if the 'Output:Surfaces:List' output exists in the IDF file.",
             call. = FALSE)
    }

    # Format output table headers
    header_name <- as.character(stringr::str_split(eio_contents[row_header], ",", simplify = TRUE))
    # Clean header characters
    header_name <- stringr::str_trim(stringr::str_replace_all(header_name, "(?:!\\s)*<(.*)>", "\\1"))
    header_name <- stringr::str_trim(stringr::str_replace_all(header_name, "^~", ""))
    header_unit <- as.character(stringr::str_split(eio_contents[row_unit], ",", simplify = TRUE))
    header_unit <- stringr::str_replace(header_unit, "! <Units>", "")
    header <- stringr::str_trim(paste(header_name, header_unit))
    col_types <- cols("HeatTransfer/Shading/Frame/Divider_Surface" = col_character(),
                      "Surface Name" = col_character(),
                      "Surface Class" = col_character(),
                      "Base Surface" = col_character(),
                      "Heat Transfer Algorithm" = col_character(),
                      "Construction/Transmittance Schedule" = col_character(),
                      "ExtBoundCondition" = col_character(),
                      "ExtConvCoeffCalc" = col_character(),
                      "IntConvCoeffCalc" = col_character(),
                      "SunExposure" = col_character(),
                      "WindExposure" = col_character(),
                      "#Sides" = col_integer(),
                      .default = col_double())

    # Raw table of surf info
    row_next_rpt <- purrr::detect(row_all, ~.x > row_unit)
    # If surface report is the last report
    if (is.null(row_next_rpt)) {
        surf_rpt <- eio_contents[row_surf:length(eio_contents)]
    } else {
        surf_rpt <- eio_contents[row_surf:(row_next_rpt -1)]
    }

    # Extract zone name per surface
    len <- length(surf_rpt)
    # Get the row number of zone info
    row_zone_start <- stringr::str_which(surf_rpt, "^(Shading_Surfaces|Zone_Surfaces),.*?,\\s*\\d")
    row_zone_end <- c(row_zone_start[-1]-1, len)
    row_zone_len <- row_zone_end - row_zone_start
    # Have to change the '# Surfaces' value as the original number excludes
    # 'Frame/Divider_Surface'.
    zone_surfaces_rev <- stringr::str_replace(surf_rpt[row_zone_start], "\\d+$", as.character((row_zone_len)))
    raw_zone_info <- stringr::str_c(rep(zone_surfaces_rev, row_zone_len), collapse = "\n")
    zone_info <- readr::read_csv(raw_zone_info,
                                 col_names = c("Zone/Shading Surfaces", "Zone Name/#Shading Surfaces", "# Surfaces"))

    # Table except sub header
    raw_per_zone <- purrr::flatten_chr(purrr::map2(row_zone_start, row_zone_len, ~{raw <- surf_rpt[(.x+1):(.x+.y)]}))
    # Supress warning messages from read_csv
    surf_info <- suppressWarnings(readr::read_csv(stringr::str_c(raw_per_zone, collapse = "\n"),
                                                  col_names = header, col_types = col_types,
                                                  na = c("", "NA", "N/A")))

    # Combine zone info and surface info per zone
    surf_info <- dplyr::bind_cols(zone_info, surf_info)

    return(surf_info)
}
# }}}1

#' @importFrom readr read_csv cols
#' @importFrom data.table as.data.table setnames
# read_meter: A function to take the path of EnergyPlus meter results and return
# a data.table of the contents with the first being a "POSIXt" column
# transformed from EnergyPlus standard "Date/Time".

# - 'meter': A path of EnergyPlus meter results. Normally a .csv file named
# (idf)Meter.csv or eplusmtr.csv.

# - 'year': An integer indicates the year value added to "Date/Time" column. If
# not specified, current calender year will be used.

# - 'eplus_date_col': The name of EnergyPlus standard datetime column. Normally
# "Date/Time".

# - 'new_date_col': A character indicates the name of the new transformed
# 'POSIXt' column.

# - 'tz': A character indicates the time zone of the transformed time column.
# The default value is the current system time zone.

# - 'rp_na': What will replace NA.

# - 'to_GJ': Whether converted the energy consumption from Joule to GigaJoule
# (1X10^9).

# - 'long': If TRUE, a long table will be returned with first column being the
# POSIXt column, and next 'component' indicating energy consumption components,
# 'type' indicating energy types (e.g. Electricity, and Gas), 'value' indicating
# the value of energy used, 'unit' indicating the unit of energy used, and
# 'timestep' indicating the tiem step of data collected. A meter output from a
# 10-min-timestep simulation will takes about 5 seconds to load.  So, use with
# caution.
# read_meter
# {{{1
read_meter <- function (meter, year = current_year(), eplus_date_col = "Date/Time",
                              new_date_col = "datetime", tz = Sys.timezone(),
                              rp_na = 0L, to_GJ = FALSE, long = FALSE) {
    meter <-
        readr::read_csv(meter, col_types = cols(.default = "d", `Date/Time` = "c")) %>%
        data.table::as.data.table() %>%
        na_replace(type = "na", replacement = rp_na) %>%
        eplus_time_trans(year = year, eplus_date_col = eplus_date_col,
                         new_date_col = new_date_col, tz = tz, keep_ori = FALSE)

    meter <- meter %>%
        data.table::setnames(col_names(., c("Electricity:Facility", "Gas:Facility")),
                             col_names(., c("Electricity:Facility", "Gas:Facility")) %>%
                                 gsub(x =.,  "(.*):(.*)\\s", "\\2:\\1 ")) %>% .[]

    if (to_GJ) {
        meter <- meter[, lapply(.SD, function(x) round(x/1E9, digits = 4)),
                       by = c(new_date_col)] %>%
                       data.table::setnames(col_names(., new_date_col, invert = TRUE),
                                            col_names(., new_date_col, invert = TRUE) %>%
                                                gsub(x = ., pattern = "\\[J\\]", replacement = "\\[GJ\\]"))
    }

    if (long) {
        meter <- long_table(meter)
    }

    return(meter)
}
# }}}1

#' @importFrom readr read_csv cols
#' @importFrom data.table as.data.table
# read_variable: A function to take the path of EnergyPlus results and return a
# data.table of the contents with the first being a "POSIXt" column transformed
# from EnergyPlus standard "Date/Time".

# - 'result': A path of EnergyPlus meter results. Normally a .csv file named
# (idf).csv or eplusout.csv.

# - 'year': An integer indicates the year value added to "Date/Time" column. If
# not specified, current calender year will be used.

# - 'eplus_date_col': The name of EnergyPlus standard datetime column. Normally
# "Date/Time".

# - 'new_date_col': A character indicates the name of the new transformed
# 'POSIXt' column.

# - 'tz': A character indicates the time zone of the transformed time column.
# The default value is the current system time zone.

# - 'rp_na': What will replace NA.

# - 'long': If TRUE, a long table will be returned with first column being the
# POSIXt column, and next 'component' indicating energy consumption components,
# 'type' indicating energy types (e.g. Electricity, and Gas), 'value' indicating
# the value of energy used, 'unit' indicating the unit of energy used, and
# 'timestep' indicating the tiem step of data collected. A meter output from a
# 10-min-timestep simulation will takes about 5 seconds to load.  So, use with
# caution.
# read_variable
# {{{1
read_variable <- function (result, year = current_year(), eplus_date_col = "Date/Time",
                               new_date_col = "datetime", tz = Sys.timezone(),
                               rp_na = NA, long = FALSE) {
    result <-
        readr::read_csv(result, col_types = cols(.default = "d", `Date/Time` = "c")) %>%
        data.table::as.data.table() %>%
        na_replace(type = "na", replacement = rp_na) %>%
        eplus_time_trans(year = year, eplus_date_col = eplus_date_col,
                         new_date_col = new_date_col, tz = tz, keep_ori = FALSE)

    if (long) {
        result <- long_table(result)
   }

    return(result)
}
# }}}1

#' @importFrom tools file_ext
#' @importFrom stringr str_subset str_replace_all str_match str_split
#' @importFrom readr read_lines
#' @importFrom data.table as.data.table setnames setcolorder
#' @importFrom rvest html_nodes html_table
#' @importFrom xml2 read_html
#' @importFrom purrr map set_names
# read_table: A function to read EnergyPlus table results.
# read_table
# {{{1
read_table <- function (file, name = c("report", "for", "table"), regex = FALSE) {
    # Check input.
    if (all(!identical(tools::file_ext(basename(file)), "htm"),
            !identical(tools::file_ext(basename(file)), "html"))) {
        stop("Input file should be a .htm/.html file.", call. = FALSE)
    }
    if (missingArg(name)) {
        stop("Please give 'name' value.", call. = FALSE)
    }
    if (any(!is.character(name), length(name) != 3)) {
        stop("'name' should be a character vector of length 3 indicating the ",
             "name of report, the name of 'for' and the name of table.", call. = FALSE)
    }

    regex_tbl_name <- "<!-- FullName:(.*)-->"
    # Get table names.
    # NOTE: Did not find a way to extract comments in htm/htmls in 'rvest'
    # package. Have to use a ugly regex method.
    tbl_name_comments <- stringr::str_subset(readr::read_lines(file), regex_tbl_name)
    tbl_full_names <- stringr::str_replace_all(tbl_name_comments, regex_tbl_name, "\\1")
    tbl_name_split <- data.table::as.data.table(stringr::str_match(tbl_full_names, "(.*)_(.*)"))
    tbl_name_split <- data.table::setnames(tbl_name_split, c("full_name", "report_for", "table"))
    tbl_name_split <- tbl_name_split[, c("report", "for") := as.data.frame(stringr::str_split(report_for, "_", 2, simplify = TRUE))][,
                                     c("full_name", "report_for") := NULL]
    tbl_names <- data.table::setcolorder(tbl_name_split, c("report", "for", "table"))

    if (!regex) {
        # Set 'which' to TRUE without '.j' will return the row number. Or can
        # use method: DT[  , .I[X=="B"] ]
        # Borrowed from: http://stackoverflow.com/questions/22408306/using-i-to-return-row-numbers-with-data-table-package
        table_id <- tbl_names[report == name[1] & `for` == name[2] & table == name[3], which = TRUE]
    } else {
        report_names <- unique(as.character(tbl_names[, report]))
        report_sel <- stringr::str_subset(report_names, name[1])

        for_names <- unique(as.character(tbl_names[, `for`]))
        for_sel <- stringr::str_subset(for_names, name[2])

        table_names <- unique(as.character(tbl_names[, table]))
        table_sel <- stringr::str_subset(table_names, name[3])

        table_id <- tbl_names[report %in% report_sel &
                              `for` %in% for_sel &
                              table %in% table_sel, which = TRUE]
    }

    if (length(table_id) == 0) {
        stop("No matched table found. Please check the value of 'name' or set ",
             "'regex' to TRUE if you want to extract multiple tables using ",
             "regular expressions.", call. = FALSE)
    }

    # Get table contents.
    tbls_raw <- rvest::html_nodes(xml2::read_html(file), "table")
    tbls <- rvest::html_table(tbls_raw[table_id], header = TRUE)

    # Get the combined table names.
    names <- tbl_names[table_id, paste0("[Report]:(", report, ") [For]:(", `for`, ") [Table]:(", table, ")")]

    # Combine table names and contents.
    tbls <- purrr::set_names(tbls, names)
    # Always rename the first column to "Components".
    tbls <- purrr::map(tbls, ~{names(.x)[1] <- "Components"; .x})

    return(tbls)

}
# }}}1