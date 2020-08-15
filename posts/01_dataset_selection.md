# Dataset Selection

As I mentioned in my [previous post](./00_init.md); in order to have some commonality between all the implementations I'll be doing, there needs to be common thread. For this project, that is going to be the same web application built around the same public dataset.

## Criteria

I have some specific criteria in the public dataset I want to use:

* A non-trivial amount of data - to me this means - it needs to be beyond what
    would easily fit in RAM on a typical machine. 
* Good documentation on the datasets structure and format.
* Multiple relations - if its just a single CSV file - not really worth it. There needs
    to have multiple record types and they need to be related in some manner.
* Include some data that would be useful to do a full text search on.
* Include some data that is geospatial so we can demonstrate PostGIS and maps / leaflet.
* Be **fun** data - that is people would be interested in looking at it.
* The domain needs to be quickly understandable by the average web application
  developer.
* Bonus if the dataset is updated regularly.
* Appropriately Licensed - I want other to be able to replicate my work.

Here's a few of the places I looked to look at lists of public datasets. There are lots of places people can go to look at lists of datasets:

* https://www.kaggle.com/
* https://datasetsearch.research.google.com/
* https://github.com/awesomedata/awesome-public-datasets
* https://registry.opendata.aws/


After spending a weekend delving through all of these lists I came up with a short list of things that look reasonable. This is completely my personal preference since I'm the one going to be working with it.

I eliminated a large swath of datasets for the following reasons

* **WAAAAYYY too little data** - A CSV with nothing but a few hundred, maybe a few thousand data points... not near enough. I want to have to think about performance at some point.
* **Lack of documentation** - If it was just a data file with no additional documentation - that is not useful. Context on how the data is collected or what the field types are is important to using it.
* **Licensing** - This dataset is going to be for demonstrations of application development and whatever else I think might be fun. So it needs to be usable by others.
* **Clearly not relational** - And I don't mean that it must be different tables, I mean that there needs to be multiple dimensions to the data, not just a row of numbers about a thing. The records need to be associated with other data that we can mashup with it.
* **Not interesting** - I'm going to spend a lot of time on this and it needs to be at least somewhat interesting and multiple ways of utilizing it need to be immediately apparent to me

## What about Sample Databases?

That's a solid history of example databases, think Northwind, Chinook, AdventureWorks, Sakila, etc. I took a look at many of them and they didn't make the cut, mostly from a size or data model complexity perspective.

## The Short List

After the weekend I ended up with this list of datasets, and they are in no particular order. Well - it is an order, the spreadsheet I had to keep track of them... they are in the order that I put them on the spreadsheet.

### Ingeinum Open Data Mashup

* <https://ingeniumcanada.org/collection-research/artifact-open-data-set-mash-up>

This looks pretty interesting - its a list of all the museum artifacts contained within the Ingeninum brands 3 museums.

* **Size** - about 100,000 records. This is on the lower end of the amount of data I'm looking for
* **Relations** - yes, some of the artifacts have sub parts, so there is are parent child relations, also keywords, countries, periods, etc. - all sorts of meta data that could be extracted out into their own tables.
* **Full Text Search** - yup - plenty - lots of descriptions, keywords, etc.
* **Geospatial** - sort of - there are country fields, that could be used to mashup with other datasets - specific lat/lon positions are not present.
* **Fun** - yeah - for sure, a database of museum artifacts - and links to the images of the artifacts is some of the data - definitely intrigues me

The data in this set is in both English and French so that could provide some interesting demonstrations of multilingual websites.

### MusicBrainz Data Dump

* <https://musicbrainz.org/>
* <https://musicbrainz.org/doc/MusicBrainz_Database>

* **Size** - definitely a good size - the downloads are about 10GB of compressed data.
* **Relations** - yup - the dataset is a PostgreSQL data dump
* **Full Text Search** - yes - artist, labels, song titles etc.
* **Geospatial** - not that I can find
* **Fun** - its music!

It is recommended that the MusicBrainz Server software be used to load the data. So this dataset appears to be tied pretty closely to existing software.

### Open Library

* <https://openlibrary.org/>
* <https://openlibrary.org/developers/dumps>

The dataset here is a complete dump of the Open Library collection. Their ultimate goal "...is to make all the published works of humankind available to everyone in the world."

* **Size** - definitely in the right size range - 55 million records over all data types - data dump is about 8GB compressed
* **Relations** - definitely - authors, works, editions, etc. the format is ultimately a JSON derivation, so somewhat self descriptive.
* **Full Text Search** - why yes - titles, authors etc.
* **Geospatial** - no
* **Fun** - its books!

One aspect of the Open Library dataset is the inclusion of all the deltas that have happened on the data. Versioned data and how to view/store it would be an additional topic to cover with this datset.

### GeoNames

* <http://www.geonames.org/>

* **Size** - 11 million place names - so good enough
* **Relations** - definitely - administrative areas, countries, regions etc.
* **Full Text Search** - yes - place names, cities, etc.
* **Geospatial** - yes - its a geopolitical database, lat lon everywhere, and some rough GeoJSON files are also available
* **Fun** - its maps!

Lots of multilingual fields here for localized place names, could be useful for multilingual examples. There is also explicit hierarchical data and showing ways to store and view this type of data would be useful.

Not sure if this would be the best as a primary data set. Could definitely enhance another data set with additional data.

### GADM

* <https://gadm.org/>

GADM provides maps and spatial data for all countries and their sub-divisions. You can browse their maps or download the data to make your own maps.

* **Size** - yes - 2GB GeoPackage - more than 300k rows of geospatial data
* **Relations** - minimal - tree of administrative areas of all countries
* **Full Text Search** - minimal - administrative area names
* **Geospatial** - very much so - full geospatial data for multiple administrative zones on planet earth.
* **Fun** - its maps!

This is in a GeoPackage file which is a SpatiaLite container with some additional structure. Mostly I think this dataset would be good to integrate with the system and use in combination with geonames.

### Internet Movie Database (IMDB)

* <https://imdb.com/>
* <https://www.imdb.com/interfaces/>
* <https://datasets.imdbws.com/>

I've used IMDB in the past as a dataset for doing demonstrations, and its always fun to look at. Not really sure if I want to use it again.

* **Size** - yes - 94 Million records.
* **Documentation** - well documented.
* **Relations** - yup - titles, crew on films, episodes, etc.
* **Full Text Search** - yes - pretty much everything could be put in search.
* **Geospatial** - no - :-( - I was hoping for some shoot location information this time.
* **Fun** - its movies!


## Decision time

I had pretty much gone through all the datasets and was whittling down this last set. I had eliminated Music Brainz as too complicated to work with, and GeoNames and GADM were nice, but I didn't think either of them would be good as the primary focus of the project. I thought they would be good add ons to a primary dataset to enhance its geopation components

So that left Ingenium vs. Open Library. I liked Ingenium from an interesting dataset perspective, but it was a bit small for my tastes. Open Library has all the data, but had basically no geospatial data.

As I was sitting there pondering this decision, an email showed up from [Unsplash](https://unsplash.com/) - the announcement of [their dataset](https://unsplash.com/data). So I took a look: 

## Unsplash Dataset - <https://unsplash.com/data>

* **Size** - yup - small one is 25,000 images, large is 2,000,000 images
* **Documentation** - yes - well documented
* **Relations** - yes - images, collections, downloads, keywords
* **Full Text Search** - yes - image meta data, keywords, etc.
* **Geospatial** - yes - images are tagged with lat/lon
* **Fun** - its images!

Okay - I think we have a winner.

Lets use the Unsplash dataset and mash it up with geonames and potentially GADM and see what comes out. I'm extremely pleased with the Unsplash dataset so far. It looks great, good documentation, it looks really fun to play with and the team is open to feedback. I've already got a [pull request merged](https://github.com/unsplash/datasets/pull/8) and [a question on data quality](https://github.com/unsplash/datasets/issues/13).

Stay tuned for many more posts to see what happens.

