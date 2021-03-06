% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/occurence_access.r
\name{correctSignSwap}
\alias{correctSignSwap}
\title{Checks if point with lat & long would concure in country shape with country
code if lat and long AND the signs of lat and long (* -1) are switched;
switched lat/long cannot exceed the dimension of valid lat/long coordinates}
\usage{
correctSignSwap(current_occ_chunk, countries)
}
\arguments{
\item{current_occ_chunk}{One data chunk from gbif containing occurences}

\item{countries}{Dataset of all countries in the world provided by
natural earth.}
}
\value{
current_occ_chunk_corrected: Corrected or unchanged but flagged
  occurences
}
\description{
Checks if point with lat & long would concure in country shape with country
code if lat and long AND the signs of lat and long (* -1) are switched;
switched lat/long cannot exceed the dimension of valid lat/long coordinates
}

