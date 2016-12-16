# GBIFsiteChecker

Checks and validates location data from the global biodiversity facility (GBIF)

## Getting Started
#Install "devtool package in R"
install.package("devtools")
#get GBIFsiteChecker from github
devtools::install_github("GBIFsiteChecker/GBIFsiteChecker")

### Prerequisites

R Studio Version 1.0.44

### Installing

Packages required
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
# # taxize soap extension for taxize utilizing soap to access the web service
# # by World register of marine species (worms)



## Running the tests
Decide on the correction level of the GBIFsiteChecker ("strict=1", "correction=2", "flagging=3"). Strict removes false data, "correction" shifts/corrects wrong data and flags them and "flagging" keeps the data as they are downloaded but flags that they are probably false. 
Enter the startup function with the desired species name, the size definition of the chunks and how many occurences should be looked at. 

# startup(species_name = "Balaenoptera musculus", records_per_chunk = 200, number_of_records = 4000,
#        correction_level = 2)


### Description of tests
The tests validate the GBIF loaction data by comparing the data to external databases: 1) the world register of marine species (WORMS) and a  natural earth data shapefile. 
If, the requested species is present in the WORMS list, and does not match any polygon from the shapefile, the occurrence is flagged as correct. If the species is not found in the WORMS list, it is assumed that the species is terrestrial and therefore is found within a polygon. Thus a point from latitude and longitude (EPSG:4326) from the GBIF data was created, which was tested to be located within a polygon of the Natural Earth shapefile. The data point was plotted in a polygon and returned the ISO2 code of the polygon which it was located in. Further, the returned ISO2 code was intersected with the ISO2 code provided by the GBIF data. In case of a matching code, the data was flagged as valid. If the data was invalid, the lat and or long or lat/long coordinates were swapped and the newly created point was rechecked. 


## Built With

* [Dropwizard](http://www.dropwizard.io/1.0.2/docs/) - The web framework used
* [Maven](https://maven.apache.org/) - Dependency Management
* [ROME](https://rometools.github.io/rome/) - Used to generate RSS Feeds

## Contributing

Please read [CONTRIBUTING.md](https://gist.github.com/PurpleBooth/b24679402957c63ec426) for details on our code of conduct, and the process for submitting pull requests to us.

## Versioning

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/your/project/tags). 

## Authors

* **Billie Thompson** - *Initial work* - [PurpleBooth](https://github.com/PurpleBooth)

See also the list of [contributors](https://github.com/your/project/contributors) who participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

* Hat tip to anyone who's code was used
* Inspiration
* etc
