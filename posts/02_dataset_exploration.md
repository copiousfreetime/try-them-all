# Exploring the Unsplash Dataset

In [01] we decided to use the [Unsplash Dataset](https://unsplash.com/data) and enhance it with the data form [GeoNames](https://www.geonames.org/) and [GADM](https://gadm.org/).

So lets look at these datasets and see what we have. We may have a bit of mucking around to do to get them into a situation that we are happy with.

## Fetching and loading the unsplash data

The Unsplash data is the core of our examples, so lets load it up according to their instructions and see where it gets us. We'll be working with the lite dataset for these articles since that is the one that is fully availble for everyone.

All the documentation for this is in the [Unsplash datasets github](https://github.com/unsplash/datasets)


1. Make a scratch directory.
    `mkdir unsplash && cd unsplash`
2. Download the dataset.
    `curl -L https://unsplash.com/data/lite/latest -# -o unsplash-research-dataset-lite-latest.zip`
3. Extract the files
    `unzip unsplash-research-dataset-lite-latest.zip`
4. Quick check on sizes
      ```sh
      % wc -l *.tsv000
       1646598 collections.tsv000
       4075505 conversions.tsv000
       2689741 keywords.tsv000
         25001 photos.tsv000
       8436845 total
      ```
5. Download the creation and loading scripts mentioned in [Loading data in PostgreSQL](https://github.com/unsplash/datasets/blob/master/how-to/psql/README.md).
    ```sh
    curl -L -O https://raw.githubusercontent.com/unsplash/datasets/master/how-to/psql/create_tables.sql
    curl -L -O https://raw.githubusercontent.com/unsplash/datasets/master/how-to/psql/load-data-client.sql
    ```
6. Create the postgresql db - this does assume you have a postgresql server up and running locally. You'll probably need to add adjust the commandline as appropriate for your situation.
    `createdb -h localhost unsplash_lite`
7. Create the tables.
    ```sh
    % psql -U jeremy  -d unsplash_lite -f create_tables.sql
    CREATE TABLE
    CREATE TABLE
    CREATE TABLE
    CREATE TABLE
    ```
8. Edit the `load-data-client.sql` file to replace the `{path}` section to the full path to this unsplash scratch directory you are in.
9. Load the data - the numbers output should equal those in Step 4 above with 1 less record per table. That's because of header lines on all the files. This will probably take a few minutes.
    ```sh
    % time psql -h localhost -U jeremy -d unsplash_lite -f load-data-client.sql
    COPY 25000
    COPY 2689739 # <-- Hmm.. this one is NOT 1 less than keywords.tsv000 above - will have to investigate that later
    COPY 1646597
    COPY 4075504

    real    1m48.452s
    user    0m57.944s
    sys     0m2.320s
    ```
## Lets go exploring!

All of the following assume you are at the `psql` commandline. So connect up: `psql -U jeremy -h localhost unplash_lite`

The fields in the dataset are [all documented](https://github.com/unsplash/datasets/blob/master/DOCS.md) and when do do a look at the tables in the db - we see the 4 tables that correspond to the 4 files.

```sql
unsplash_lite=# \d
               List of relations
 Schema |         Name         | Type  | Owner
--------+----------------------+-------+--------
 public | unsplash_collections | table | jeremy
 public | unsplash_conversions | table | jeremy
 public | unsplash_keywords    | table | jeremy
 public | unsplash_photos      | table | jeremy
(4 rows)
```

One thing of note - when we take a look at the [create_tables.sql](https://github.com/unsplash/datasets/blob/master/how-to/psql/create_tables.sql) we notice that there are no other indexes than primary keys - so depending on how we use thei dataset we may want to add additional indexes.


### Data Quality checks

#### Check Referential interity

The `unsplash_photos.photo_id` field is the primary key of all the photos, and the `photo_id` column in the other tables should refer to the photos table.

```sql
select count(*) from unsplash_collections where not exists (select 1 from unsplash_photos where photos_id = unsplash_collections.photo_id);
select count(*) from unsplash_conversion  where not exists (select 1 from unsplash_photos where photos_id = unsplash_conversion.photo_id);
select count(*) from unsplash_keywords    where not exists (select 1 from unsplash_photos where photos_id = unsplash_keywords.photo_id);
```

All of those returned `0` rows - so that's good, no orphaned rows. Since this is good, and the original [create-tables.sql](https://github.com/unsplash/datasets/blob/master/how-to/psql/create_tables.sql) does not mark any foreign key constraints - we'll proably want to add those in.

#### Cardinality check

One of the first things I do when looking at a new set of data is check out what might be some data quality problems. The cardinality of the various columns is always a good place to start. This can show you potential places where there may be errors in the dataset, or places that need to be cleaned up.

When I first looked at the 1.0.0 version of the dataset, and was doing this, I saw that the `unsplash_photos.ai_primary_landmark_*` fields were all `NULL`. [I asked a question on githup about it](https://github.com/unsplash/datasets/issues/12) and it turned out to be a bug. Lets check out what the situation is now.

```sql
  select ai_primary_landmark_name, count(*) from unsplash_photos group by 1 order by 2 desc limit 10;
```

Stil lots of NULLs, but that's better than all NULL;

```text
        ai_primary_landmark_name         | count
-----------------------------------------+-------
                                         | 23885
 Yosemite National Park                  |    25
 Banff National Park                     |    20
 Skógafoss                               |    19
 Yosemite National Park, Half Dome       |    17
 Antelope Canyon                         |    17
 Pragser Wildsee                         |    17
 Yosemite National Park, Yosemite Valley |    16
 Zion National Park                      |    13
 Parco naturale di Fanes-Sennes-Braies   |    13
(10 rows)
```

Another one that looks like it could be a potential issue is the `unsplash_photos.photo_featured` column. Its a boolean column, but all the values are true.

```text
unsplash_lite=# select photo_featured, count(*) from unsplash_photos group by 1;
 photo_featured | count
----------------+-------
 t              | 25000
```

#### Check for leading and trailing whitespace on text fields.

If we look at the `unsplash_keywords` table - we see that there is a keywords column - I wonder what the shape of that is. Are the keywords stripped of leanding and trailing spaces?

```text
unsplash_lite=# select count(*) from unsplash_keywords where keyword like ' %';
 count
-------
  1248

unsplash_lite=# select count(*) from unsplash_keywords where keyword like '% ';
 count
-------
   291
```

That could be an issue -  lets see if there's any any keywords that are just padded left or right with spaces.

```text
unsplash_lite=#  select keyword, count(*)  from unsplash_keywords where keyword like '% ' group by 1 order by 2 desc limit 5;
     keyword      | count
------------------+-------
 wallpaper        |     5
 california       |     5
 cat photography  |     4
 beautiful        |     4
  silhouette      |     3

unsplash_lite=# select '>' || keyword || '<', count(*) from unsplash_keywords where keyword IN (' wallpaper', 'wallpaper', 'wallpaper ') group by 1 order by 2 desc;
   ?column?   | count
--------------+-------
 >wallpaper<  |  1951
 > wallpaper< |    12
 >wallpaper < |     5
```

Yup -- looks like thre might be something to this - we'll [ask Unsplash about it](https://github.com/unsplash/datasets/issues/13#issuecomment-674709294). there's a whole lot of text fields in the Unsplash data - I did run through through all of them to see which ones had leading and trailing spaces. I'll probably open up a ticket with them regarding this.

* `unsplash_photos.exif_camera_make`
* `unsplash_photos.exif_camera_model`
* `unsplash_photos.photo_location_name`
* `unsplash_photos.photo_location_country`
* `unsplash_photos.photo_location_city`
* `unsplash_conversions.keyword`

#### How about if the keywords are normalized on case?

```
unsplash_lite=# select count(*) from unsplash_keywords where keyword != lower(keyword);
 count
-------
     0
```

Okay - that looks good.

