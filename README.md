# GBIFsiteChecker

Checks and validates location data from the global biodiversity facility (GBIF)

## Getting Started
Install devtool package in R
install.package("devtools")
get GBIFsiteChecker from github
devtools::install_github("GBIFsiteChecker/GBIFsiteChecker")

## Prerequisites

R Version >= 3.2.3

## Example
Decide on the correction level of the GBIFsiteChecker ("strict=1", "correction=2", "flagging=3"). Strict removes false data, "correction" shifts/corrects wrong data and flags them and "flagging" keeps the data as they are downloaded but flags that they are probably false. 
Enter the startup function with the desired species name, the size definition of the chunks and how many occurences should be looked at. 

startup(species_name = "Balaenoptera musculus", records_per_chunk = 200, number_of_records = 4000,
        correction_level = 2)


## Description of the example
The tests validate the GBIF loaction data by comparing the data to external databases: 1) the world register of marine species (WORMS) and a  natural earth data shapefile. 
If, the requested species is present in the WORMS list, and does not match any polygon from the shapefile, the occurrence is flagged as correct. If the species is not found in the WORMS list, it is assumed that the species is terrestrial and therefore is found within a polygon. Thus a point from latitude and longitude (EPSG:4326) from the GBIF data was created, which was tested to be located within a polygon of the Natural Earth shapefile. The data point was plotted in a polygon and returned the ISO2 code of the polygon which it was located in. Further, the returned ISO2 code was intersected with the ISO2 code provided by the GBIF data. In case of a matching code, the data was flagged as valid. If the data was invalid, the lat and or long or lat/long coordinates were swapped and the newly created point was rechecked.

## Existing Problems
Accumulation of occurrences in a cental position of countries 
(originates from recorded occurrences without coordinates that are artifically relocated in the center of the respecitve country)


Another issue to be addressed is the lacking ISO2 code in some presumably correct data, which are marked uncertain, in the GBIFsiteChecker. Another matter to be taken into account is the assumption that all data were entered into GBIF in WGS84, a claim from GBIF that could or could not hold true. Ideally, there needs to be a check to validate this ellipsoid as entry standard.
A shortcoming of the in GBIFsiteChecker implemented division of marine and terrestrial species, is the possibility of aerial species, such as doves that could be detected both on land and the ocean. Thus, an extension addressing aerial species is required. 
Generally, other validation checks could be implemented to make the GBIFsiteChecker even more precise, such as a match of elevation of occurrences to the shapefiles, increasing the check precision from two to three dimensions.
Furthermore, there are various options to make the package more user friendly. The implementation of a lookup occurrences via SpeciesKey could be one of them. \\
Most importantly, the location is just one of the dimensions that needs to be corrected in the GBIF database. A previously mentioned, time, taxonomic denomination and location are parameters where systematic erroneous data can be detected. The ultimate goal of a systematic GBIF data cleanup would take the taxonomic, temporal and spacial issues into account. 
