# Aufgabe: Generating species richness data GBIF requires several steps:
# rgbif geogr. correction, R::taxis, sampling bias, richness
# This project builds the pipiline for future use.

##
## Install required packages
##
# install.packages("sp")
# install.packages("raster")
# install.packages("XML")
# install.packages("lattice")
# install.packages("grid")
# install.packages("foreign")
# install.packages("maptools")
# install.packages("dismo")
# install.packages("curl")
# install.packages("httr")
# install.packages("rgeos")
# install.packages("rgbif")
# install.packages("taxize")
# install.packages("rgdal")
# install.packages("devtools")
# install.packages("doParallel")
# install.packages("doSNOW")
#
# # taxize soap extension for taxize utilizing soap to access the web service
# # by World register of marine species (worms)

library(devtools)

install.packages(c("XMLSchema", "SSOAP"), 
                 repos = c("http://packages.ropensci.org", 
                           "http://cran.rstudio.com"))
devtools::install_github("ropensci/taxizesoap")

##
## Load required Packages
##
loadLibaries <- function() {
  library(sp)
  library(raster)
  library(XML)
  library(lattice)
  library(grid)
  library(foreign)
  library(maptools)
  library(rgbif)    # doc: https://cran.r-project.org/web/packages/rgbif/rgbif.pdf
  library(dismo)
  library(rgdal)
  library(utils)
  library(foreach)
  library(doParallel)
  library(doSNOW)
  library(rgeos)
  library(taxizesoap)
}

##
## Initialize and setup environment
##

#' Loading data from the gbif database
#' @param species_name Specify the name of the species in order to download the
#'   data from the gbif database
#' @param start Specify the start index to begin the download with
#' @param limit Specify the number of occurrences to download (max: 200.000)
initData <- function(species_name, start = 0, limit = 200) {
  occ <- occ_search(scientificName = species_name, limit = limit,
                    hasCoordinate = TRUE, start = start)
  return (occ)
}

#' Get the number of occurrences for a specific species
#' @param species_name Name of the species to load
#' @return species$meta$count - The number of occurrences for the specified
#'   species
getNumberOfOccurences <- function(species_name) {
  species <- initData(species_name = species_name, start = 0, limit = 1)
  return (species$meta$count)
}

#' Get the species properties from the worms database to check marine species
#' with failing location check
#' @param species_name Name of the species to get the properties for
#' @return speciesOpts - habitat properties of the named species
getSpeciesOpts <- function(species_name) {
  # query the worms database for habitat
  worms <- worms_records(scientific=species_name)
  # setup a list with species properties
  speciesOpts <- list()
  if (NROW(worms) == 0 && NCOL(worms) == 0) {
    speciesOpts$isMarine <- 0
  } else {
    speciesOpts$isMarine <- max(worms$isMarine, na.rm = TRUE)
  }
  return (speciesOpts)
}

#' Download spatial data from natural earth and unzip it
initLocation <- function() {
  # load all countries of the world
  countries_name <- "countries.zip"
  if (!file.exists("countries.zip")) {
    download.file(url = paste("http://www.naturalearthdata.com/http//",
                              "www.naturalearthdata.com/download/50m/cultural/",
                              "ne_50m_admin_0_countries.zip", sep = ""),
                  destfile = countries_name)
    unzip(countries_name)
  }
}

#' Read the shape file utilizing the rgdal package
openShape <- function() {
  # check for supported file formats
  # ogrDrivers()
  # open vector file (esri-shapeformat)
  countries <- try(readOGR(dsn="ne_50m_admin_0_countries.shp"))
  return (countries)
}

##
## Processing methods for iterative use
##

#' Checks if lat, long locations concurs with country codes. Checks lat, long
#' if lat, long lies within country shape
#' @param current_occ_chunk One data chunk from gbif containing occurences
#' @param countries Dataset of all countries in the world provided by
#'   natural earth.
#' @return check_result: Boolean values indicating if the locations of the
#'   occurences are in the given countries - true - correct, false - incorrect
checkLocation <- function(current_occ_chunk, countries, species_opts) {

  # create empty result container
  # by default the points and the countries do not match
  check_result <- logical(NROW(current_occ_chunk$data))

  # access location parameter from current original occurence
  lat <- current_occ_chunk$data$decimalLatitude
  long <- current_occ_chunk$data$decimalLongitude
  countryCode <- current_occ_chunk$data$countryCode

  # create spatial point from lat, long
  current_occ_points <- SpatialPointsDataFrame(cbind(long, lat),
                                               data = current_occ_chunk$data)
  # reproject points and countries to global metric projection
  # using pseudo transmercator projection
  proj4string(current_occ_points) <- proj4string(countries)
  current_occ_points_3857 <- spTransform(current_occ_points,
                                         CRS("+init=epsg:3857"))
  countries_3857 <- spTransform(countries, CRS("+init=epsg:3857"))

  # Use buffer arround the countries to match also the points which are
  # inaccurate and lie at the coast side
  # positive buffer for terrestial species which are located in the sea
  # negative buffer for marine species which are located on land
  if (species_opts$isMarine == 0) {
    country_buffer_3857 <- gBuffer(countries_3857, width = 10000, byid = TRUE)
  } else if (species_opts$isMarine == 1) {
    country_buffer_3857 <- gBuffer(countries_3857, width = -10000, byid = TRUE)
  }
  # Check all points from a chunk against all countries
  intersectingPolygons <- over(current_occ_points_3857, country_buffer_3857)

  # Marine check
  nonIntersectingPoints_idx <- which(is.na(intersectingPolygons$type))
  intersectingPoints_idx <- which(!is.na(intersectingPolygons$type))

  # not intersecting points
  if (species_opts$isMarine == 1) { # Marine species only live in the sea
    check_result[nonIntersectingPoints_idx] <- TRUE
    check_result[intersectingPoints_idx] <- FALSE
  } else { # Terrestial species only live on land
    check_result[nonIntersectingPoints_idx] <- FALSE
    check_result[intersectingPoints_idx] <- TRUE

    # get indexes from country codes which are not NA
    valid_CountryCodes_idx <- which(!is.na(countryCode))
    # get indexes from polygon iso codes which are not NA
    valid_PolygonIsoCodes_idx <- which(!is.na(intersectingPolygons$iso_a2))
    # combine the two indices to get all valid intersections
    valid_idx <- intersect(valid_CountryCodes_idx, valid_PolygonIsoCodes_idx)
    # check iso and country codes for valid indices
    check_result[valid_idx] <- countryCode[valid_idx] ==
      intersectingPolygons[valid_idx,]$iso_a2
  }
  return (check_result)
}

#' Tries to correct the locations by swapping the sign of lat, long, latlong &
#' checks if the lat long of the point concurs the country shape with the
#' country code
#' @param current_occ_chunk One chunk of several gbif occurence
#' @param countries Dataset of all countries in the world provided by
#'   natural earth.
#' @return current_occ_chunk_corrected: Corrected or unchanged but flagged
#'   occurences
correctSign <- function(current_occ_chunk, countries, species_opts) {
  # prepare temporal correction for each check
  corrected_current_occ_chunk_lat <- current_occ_chunk
  corrected_current_occ_chunk_long <- current_occ_chunk
  corrected_current_occ_chunk_latlong <- current_occ_chunk

  # access original location parameter from current occurence
  lat <- current_occ_chunk$data$decimalLatitude
  long <- current_occ_chunk$data$decimalLongitude

  # apply correction
  # swapped lat
  corrected_current_occ_chunk_lat$data$decimalLatitude <- -1 * lat
  # swapped long
  corrected_current_occ_chunk_long$data$decimalLongitude <- -1 * long
  # swapped lat and long
  corrected_current_occ_chunk_latlong$data$decimalLatitude <- -1 * lat
  corrected_current_occ_chunk_latlong$data$decimalLongitude <- -1 * long

  # recheck location for each modification
  isCorrectedLocationLatCorrect <- checkLocation(
    current_occ_chunk = corrected_current_occ_chunk_lat, countries = countries,
    species_opts = species_opts)
  isCorrectedLocationLongCorrect <- checkLocation(
    current_occ_chunk = corrected_current_occ_chunk_long, countries = countries,
    species_opts = species_opts)
  isCorrectedLocationLatLongCorrect <- checkLocation(
    current_occ_chunk = corrected_current_occ_chunk_latlong,
    countries = countries, species_opts = species_opts)
  current_occ_chunk_corrected <- current_occ_chunk

  # indices of corrected occurences for each modification
  lat_correct_idx <- which(isCorrectedLocationLatCorrect)
  long_correct_idx <- which(isCorrectedLocationLongCorrect)
  latlong_correct_idx <- which(isCorrectedLocationLatLongCorrect)

  # adopt corrected and checked modification to the original data and flag
  # modification for each type of modification.
  # set initial correction flag to incorrect data (3) - change modification flag
  # if modification is adopted (2)
  current_occ_chunk_corrected$data$correction_flag <- 3
  if (length(lat_correct_idx) > 0) { # adopt lat modification
    current_occ_chunk_corrected$data[lat_correct_idx,] <-
      corrected_current_occ_chunk_lat$data[lat_correct_idx,]
    current_occ_chunk_corrected$data[lat_correct_idx,]$correction_flag <- 2
  } else if (length(long_correct_idx) > 0) { # adopt long modification
    current_occ_chunk_corrected$data[long_correct_idx,] <-
      corrected_current_occ_chunk_long$data[long_correct_idx,]
    current_occ_chunk_corrected$data[long_correct_idx,]$correction_flag <- 2
  } else if (length(latlong_correct_idx) > 0) { # adopt latlong modification
    current_occ_chunk_corrected$data[latlong_correct_idx,] <-
      corrected_current_occ_chunk_latlong$data[latlong_correct_idx,]
    current_occ_chunk_corrected$data[latlong_correct_idx,]$correction_flag <- 2
  }
  return (current_occ_chunk_corrected)
}

#' Checks if point with lat & long would concure in country shape with country
#' code if lat and long are swapped;
#' switched lat/long cannot exceed the dimension of valid lat/long numbers
#' @param current_occ_chunk One data chunk from gbif containing occurences
#' @param countries Dataset of all countries in the world provided by
#'   natural earth.
#' @return current_occ_chunk_corrected: Corrected or unchanged but flagged
#'   occurences
correctSwap <- function(current_occ_chunk, countries, species_opts) {

  corrected_current_occ_chunk_swapped <- current_occ_chunk

  # access original location parameter from current occurence
  lat <- current_occ_chunk$data$decimalLatitude
  long <- current_occ_chunk$data$decimalLongitude

  # swap lat long only if swap does not exceed bounding box of
  # coordinate system.
  valid_lat_idx <- which(long <= 90 && long >= -90)

  # actual swap
  corrected_current_occ_chunk_swapped$data$decimalLatitude[valid_lat_idx] <-
    long[valid_lat_idx]
  corrected_current_occ_chunk_swapped$data$decimalLongitude[valid_lat_idx] <-
    lat[valid_lat_idx]

  # recheck location
  isCorrectedLocationSwapCorrect <- checkLocation(
    current_occ_chunk = corrected_current_occ_chunk_swapped,
    countries = countries, species_opts = species_opts)

  current_occ_chunk_corrected <- current_occ_chunk

  # get indices of corrected and checked data
  swap_correct_idx <- which(isCorrectedLocationSwapCorrect)

  # adopt corrected and checked data to original chunk
  if (length(swap_correct_idx) > 0) {
    current_occ_chunk_corrected$data[swap_correct_idx,] <-
      corrected_current_occ_chunk_swapped$data[swap_correct_idx,]
    current_occ_chunk_corrected$data[swap_correct_idx,]$correction_flag <- 2
  }
  return (current_occ_chunk_corrected)
}

#' Checks if point with lat & long would concure in country shape with country
#' code if lat and long AND the signs of lat and long (* -1) are switched;
#' switched lat/long cannot exceed the dimension of valid lat/long coordinates
#' @param current_occ_chunk One data chunk from gbif containing occurences
#' @param countries Dataset of all countries in the world provided by
#'   natural earth.
#' @return current_occ_chunk_corrected: Corrected or unchanged but flagged
#'   occurences
correctSignSwap <- function(current_occ_chunk, countries, species_opts) {
  corrected_current_occ_chunk_sign_swapped <- current_occ_chunk

  # access original location parameter from current occurence
  lat <- current_occ_chunk$data$decimalLatitude
  long <- current_occ_chunk$data$decimalLongitude

  # swap lat long only if swap does not exceed bounding box of
  # coordinate system.
  valid_lat_idx <- which(long <= 90 && long >= -90)

  # actual lat long swap
  corrected_current_occ_chunk_sign_swapped$data$
    decimalLatitude[valid_lat_idx] <- long[valid_lat_idx]
  corrected_current_occ_chunk_sign_swapped$data$
    decimalLongitude[valid_lat_idx] <- lat[valid_lat_idx]

  # apply swapped data to sign correction
  corrected_current_occ_chunk_sign_swapped <-
    correctSign(corrected_current_occ_chunk_sign_swapped, countries, 
                species_opts)

  # recheck location
  isCorrectedLocationSwapCorrect <- checkLocation(
    current_occ_chunk = corrected_current_occ_chunk_sign_swapped,
    countries = countries, species_opts = species_opts)

  current_occ_chunk_corrected <- current_occ_chunk

  # get indices of corrected and checked data
  swap_correct_idx <- which(isCorrectedLocationSwapCorrect)

  # adopt corrected and checked data to original chunk
  if (length(swap_correct_idx) > 0) {
    current_occ_chunk_corrected$data[swap_correct_idx,] <-
      corrected_current_occ_chunk_sign_swapped$data[swap_correct_idx,]
    current_occ_chunk_corrected$data[swap_correct_idx,]$correction_flag <- 2
  }
  return (current_occ_chunk_corrected)
}

#' Prepares pipline check and enables the three different output-modes:
#' strict (delete errorneous data),
#' correction (try to correct the data),
#' uncertain (flag errorneous data but dont correct)
#' @param fun Function to apply to the pipeline and work according to correction
#'   level.
#' @param current_occ_chunk Original chunk of occurences before correction and
#'   flagging. Might be preprocessed data from a previous check.
#' @return current_occ_chunk_corrected: Corrected or unchanged but flagged
#'   occurences
pipeline_generic_check <- function(fun, current_occ_chunk, countries, 
                                   species_opts, correction_level) {
  current_occ_chunk_corrected <- current_occ_chunk

  # make an initial location check
  isLocationCorrect <- checkLocation(
    current_occ_chunk = current_occ_chunk, countries = countries,
    species_opts = species_opts)
  # get the indices of the incorrect records which have to be corrected
  locationIncorrect_idx <- which(!isLocationCorrect)
  # apply different modification or correction modi
  if (length(locationIncorrect_idx) > 0) { # Location is incorrect
    if (correction_level == 3) { # strict mode
      current_occ_chunk_corrected$data <- current_occ_chunk_corrected$data[-locationIncorrect_idx,]
    } else if (correction_level == 2) { # correction mode
      # correct only terrestial data, because it can be checked against
      # iso or country codes
      if (species_opts$isMarine == 0) {
        correctedLocations <- fun(
          current_occ_chunk = current_occ_chunk, countries = countries,
          species_opts = species_opts)
        current_occ_chunk_corrected$data[locationIncorrect_idx,] <-
          correctedLocations$data[locationIncorrect_idx,]
      } else {
        current_occ_chunk_corrected$data[locationIncorrect_idx,]$
          correction_flag <- 3
      }
    } else if (correction_level == 1) { # uncertain flag mode
      current_occ_chunk_corrected$data[locationIncorrect_idx,]$
        correction_flag <- 4
    }
  }
  return (current_occ_chunk_corrected)
}

#' Feeding pipline (consinsting of the defined functions) with current_occ_chunk
#' and receiving the output result (with corrected or flagged output)
#' @param current_occ_chunk
#' @return current_occ_chunk_corrected: Corrected or unchanged but flagged
#'   occurences
pipeline <- function(current_occ_chunk, countries, species_opts, 
                     correction_level) {
  current_occ_chunk_corrected <- current_occ_chunk
  current_occ_chunk_corrected$data$correction_flag <- 1

  # apply the different kind of correction to the data passing the pipeline
  # sign correction
  current_occ_chunk_corrected <- pipeline_generic_check(
    fun = correctSign, current_occ_chunk = current_occ_chunk_corrected, 
    countries = countries, species_opts = species_opts, 
    correction_level = correction_level)
  # swap correction
  current_occ_chunk_corrected <- pipeline_generic_check(
    fun = correctSwap, current_occ_chunk = current_occ_chunk_corrected, 
    countries = countries, species_opts = species_opts,
    correction_level = correction_level)
  # sign + swap correction
  current_occ_chunk_corrected <- pipeline_generic_check(
    fun = correctSignSwap, current_occ_chunk = current_occ_chunk_corrected, 
    countries = countries, species_opts = species_opts,
    correction_level = correction_level)

  return (current_occ_chunk_corrected)
}

cropWorld <- function(occ, countries) {
  minLong <- 180
  maxLong <- -180
  minLat <- 90
  maxLat <- -90
  for (i in 1:NROW(occ)) {
    validLong <- which(!is.na(occ[i,]$data$decimalLongitude))
    validLat <- which(!is.na(occ[i,]$data$decimalLatitude))
    iminLong <- min(occ[i,]$data$decimalLongitude[validLong])
    imaxLong <- max(occ[i,]$data$decimalLongitude[validLong])
    iminLat <- min(occ[i,]$data$decimalLatitude[validLat])
    imaxLat <- max(occ[i,]$data$decimalLatitude[validLat])
    if (iminLong < minLong) {
      minLong <- iminLong
    }
    if (imaxLong > maxLong) {
      maxLong <- imaxLong
    }
    if (iminLat < minLat) {
      minLat <- iminLat
    }
    if (imaxLat > maxLat) {
      maxLat <- imaxLat
    }
  }
  print(paste("minLong: ", minLong, " maxLong: ", maxLong, " minLat: ", minLat, 
              " maxLat: ", maxLat))
  out <- crop(countries, extent(minLong - 10, maxLong + 10, minLat - 10,
                                maxLat + 10))
  # Expand right side of clipping rect to make room for the legend
  par(xpd = FALSE,mar=c(5.1, 4.1, 4.1, 4.5))
  #DEM with a custom legend
  plot(out, col = "gainsboro", lwd = 0.2)
  par(xpd = TRUE)
  #add a legend - but make it appear outside of the plot
  legend(x = "bottom", legend = c("correct", "corrected", "invalid", "uncertain"),
         inset=c(-0.15,0), col=c("#0571b0","cyan", "#ca0020", "#f4a582"), 
         cex = 0.75, title = "GBIF-data", pch = c(15))
}

#' Plot one occurence based on the correction_flag
#' @param current_occ Current occurence for plotting
#' @param countries countries Dataset of all countries in the world provided by
#'   natural earth.
plotPoint <- function(occ, countries) {
  for (i in 1:NROW(occ)) {
    current_occ <- occ[i,]$data
    # access location parameter from current occurence
    lat <- current_occ$decimalLatitude
    long <- current_occ$decimalLongitude
    if (!is.na(lat) || !is.na(long)) {
      # create point from lat, long
      current_occ_point <- SpatialPoints(cbind(long, lat))
      proj4string(current_occ_point) <- proj4string(countries)
      points(current_occ_point, col =
               ifelse(current_occ$correction_flag == 1,'#0571b0',
                      ifelse(current_occ$correction_flag == 2, "cyan",
                             ifelse(current_occ$correction_flag == 3, "#ca0020",
                                    "#f4a582"))), pch = '·', cex=2)
    }
  }
}

#' Main loop to iterate over all occurences with variables chunks
#' (variable in size an number)
#' @param species_name Name of the species to download the occurences
#' @param countries All countries of the world from shapefile to make
#'   location checks.
#' @param correction_level A number defining the level of correction:
#'   1 - flag (flag and dont correct invalid data),
#'   2 - correct (flag and correct invalid data),
#'   3 - strict (remove invalid data)
#' @return correctedData - Checked and corrected location gbif data
mainLoop <- function(species_name, countries, correction_level,
                     records_per_chunk, number_of_records, species_opts,
                     progressbar = TRUE) {
  number_of_chunks <- ceiling(number_of_records / records_per_chunk)
  print(paste("Number of chunks: ", number_of_chunks))

  # set up progress bar
  if(progressbar) {
    pb <- txtProgressBar(min = 0, max = number_of_chunks, style = 3)
    progress <- function(n) setTxtProgressBar(pb, n)
    opts <- list(progress = progress)
  }
  # use all cores available, except 1
  cores <- parallel::detectCores() - 1
  # set up computation cluster
  cl <- parallel::makeCluster(cores)
  doSNOW::registerDoSNOW(cl)

  correctedData <-
    foreach::foreach(i = 0:number_of_chunks, .combine = rbind,
     .options.snow = opts, .export =
       c("initData", "pipeline", "checkLocation", "correction_level",
         "correctSign", "correctSwap", "correctSignSwap", "species_opts",
         "pipeline_generic_check"),
     .packages = c("rgbif", "rgeos", "sp")) %dopar% {

       # Load gbif data
       current_occ_chunk <- initData(
         species_name = species_name,
         start = i * records_per_chunk,
         limit = (i + 1) * records_per_chunk - 1)

       if (is.null(current_occ_chunk$data)) {
         stop("No data found!")
       }
       # start the pipeline
       corrected_data <- pipeline(current_occ_chunk = current_occ_chunk, 
                                  countries = countries, 
                                  species_opts = species_opts,
                                  correction_level = correction_level)
    }
  # stop cluster, free memory form workers
  parallel::stopCluster(cl = cl)
  close(pb)
  return (correctedData)
}

#' entry point of the package and decide for level of correction
#' @param correction_level A number defining the level of correction:
#'   1 - flag (flag and dont correct invalid data),
#'   2 - correct (flag and correct invalid data),
#'   3 - strict (remove invalid data)
#' @param species_name
#' @param limit
startup <- function(species_name, number_of_records, records_per_chunk,
                    correction_level = 2) {
  loadLibaries()
  correction_level <- correction_level
  # Load shape file
  initLocation()
  countries <- openShape()

  # Load species properties from worms
  species_opts <- getSpeciesOpts(species_name)

  # start parallelized loop to iterate over chunks containing a subset of all
  # occurences
  result <- mainLoop(species_name = species_name,  countries = countries,
                     correction_level = correction_level,
                     records_per_chunk = records_per_chunk,
                     number_of_records = number_of_records,
                     species_opts = species_opts)

  # plot the world depending on the extent of the result
  cropWorld(occ = result, countries = countries)
  # plot the whole composed result
  plotPoint(occ = result, countries = countries)

  return (result)
}
# do some testing
# land species
# startup(species_name = "Ciconia ciconia", records_per_chunk = 250, number_of_records = 2000,
#        correction_level = 2)
startup(species_name = "Ursus americanus", records_per_chunk = 100, number_of_records = 100,
        correction_level = 1)
# startup(species_name = "Chamaerops humilis", records_per_chunk = 200, number_of_records = 100,
#        correction_level = 2)
# startup(species_name = "Scardinius erythrophthalmus", records_per_chunk = 200, number_of_records = 500,
#         correction_level = 2)
# marine species
# startup(species_name = "Balaenoptera musculus", records_per_chunk = 200, number_of_records = 4000,
#        correction_level = 2)
# startup(species_name = "Delphinus delphis", records_per_chunk = 200, number_of_records = 4000,
#         correction_level = 2)
