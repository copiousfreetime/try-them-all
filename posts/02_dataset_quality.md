# Exploring the Data Quality of the Unsplash Dataset

In the [previous article](https://dojo4.com/blog/try-them-all-dataset-selection) I decided to use the [Unsplash Dataset](https://unsplash.com/data) and enhance it with the data from [GeoNames](https://www.geonames.org/) and [GADM](https://gadm.org/).

Today I'm going to explore the data of the Unsplash dataset from a data quality perspective. I want to check things out about the data that could trip me down the road if I don't catch them now.

## Fetching and loading the Unsplash data

This process is all derived from the documentation in the [Unsplash datasets github repository](https://github.com/unsplash/datasets).

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
6. Create the postgresql db - this does assume you have a postgresql server up and running locally. You'll probably need to adjust the commandline as appropriate for your situation.
    `createdb -h localhost unsplash_lite`
7. Create the tables.
    ```txt
    % psql -U jeremy  -d unsplash_lite -f create_tables.sql
    CREATE TABLE
    CREATE TABLE
    CREATE TABLE
    CREATE TABLE
    ```
8. Edit the `load-data-client.sql` file to replace the `{path}` section to the full path to the unsplash scratch directory you are in.
9. Load the data - the numbers output should be 1 less than those  in the `wc -l` check from Step 4 above. That's because of header lines on all the files. This will probably take a few minutes.
    ```txt
    % time psql -h localhost -U jeremy -d unsplash_lite -f load-data-client.sql
    COPY 25000
    COPY 2689739 # <-- Hmm.. this one is NOT 1 less than keywords.tsv000 above - will have to investigate
    COPY 1646597
    COPY 4075504

    real    1m48.452s
    user    0m57.944s
    sys     0m2.320s
    ```

## Data Quality Checks

It is always a good idea when you start looking at a dataset to do some cursory data quality checks and see if anything jumps out.

All of the following assume you are at the `psql` commandline. So connect up: `psql -U jeremy -h localhost unplash_lite`

### Check Referential Integrity

According to the [dataset documentation](https://github.com/unsplash/datasets/blob/master/DOCS.md) the `photo_id` column on the `unsplash_photos.photo_id` field is the primary key of all the photos, and the `photo_id` column in the other tables should refer to the photos table. The [create_tables.sql](https://github.com/unsplash/datasets/blob/master/how-to/psql/create_tables.sql) does not create the referential constraint - or indexes on these columns. Lets add those. Doing so will confirm the documented referential integrity.

```txt
unsplash_lite=# alter table unsplash_collections add foreign key (photo_id) references unsplash_photos(photo_id);
ALTER TABLE
unsplash_lite=# alter table unsplash_conversions add foreign key (photo_id) references unsplash_photos(photo_id);
ALTER TABLE
unsplash_lite=# alter table unsplash_keywords add foreign key (photo_id) references unsplash_photos(photo_id);
ALTER TABLE
```

No errors. Excellent, this confirms the documented referential integrity.

Just to save our sanity while doing some exploring - lets go ahead and add indexes on those foreign key columns. No need to add one for `unsplash_collections` as it is part of the compound primary key.

```txt
unsplash_lite=# create index on unsplash_conversions(photo_id);
CREATE INDEX
unsplash_lite=# create index on unsplash_keywords(photo_id);
CREATE INDEX
```

### Cardinality check

One of the first things I do when looking at a new set of data is check out the cardinality of the columns. In other words, the list of distinct values in the column. This can show you potential errors or just undocumented assumptions in the dataset.

You could also use a tool like [xsv](https://github.com/BurntSushi/xsv) to do an initial cardinality report. Something like `xsv stats --cardinality -d '\t' photos.tsv000  | xsv table` will work.

I'm going with an SQL approach today. Doing a cardinality check is effectively doing a group count on all the values of a column. This query on `unsplash_photos.photo_featured` for example.

```txt
unslash_lite=# select photo_featured, count(*) from unsplash_photos group by 1;
 photo_featured | count
----------------+-------
 t              | 25000
(1 row) 
```

This shows that the `unsplash_photos.photo_featured` field has the value`true` for every record in the dataset. A cardinality of 1. When a column has a cardinality of 1, it is always [worth confirming](https://github.com/unsplash/datasets/issues/25) that this cardinality is correct. In this case [this is expected](https://github.com/unsplash/datasets/issues/25#issuecomment-677794892).

  > It is expected that all the photos in the Lite dataset are featured photos. It won't be the case in the Full dataset
  > -- [@TimmyCarbone](https://github.com/unsplash/datasets/issues/25#issuecomment-677794892)

The first version of the Unsplash dataset I downloaded was the initial release. And when I did cardinality checks on the various `unsplash_photos.ai_primary_landmark_*` columns, they all had a cardinality of 1, with the value `NULL`. [I asked about this](https://github.com/unsplash/datasets/issues/12). And it turned out to be a bug, was fixed, and a new release of the dataset was published.

So always worth worth asking questions. Initial clarifications can save hours, days, weeks, even months of person time to find, fix, and reprocess incorrect data assumptions.


### Check for leading and trailing whitespace on text fields.

Looking at the `unsplash_keywords` table, there is a `keyword` column. If the values in this column are from human entered data, in all probability it will be a bit messy. For instance, do any of the keywords have leading or trailing spaces?

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

That could be an issue -- lets see if there's any any keywords that are just padded left or right with spaces.

```text
unsplash_lite=# select keyword, count(*)  from unsplash_keywords where keyword like '% ' group by 1 order by 2 desc limit 5;
     keyword      | count
------------------+-------
 wallpaper        |     5
 california       |     5
 cat photography  |     4
 beautiful        |     4
  silhouette      |     3

unsplash_lite=# select '>' || keyword || '<' as keyword, count(*) from unsplash_keywords where keyword IN (' wallpaper', 'wallpaper', 'wallpaper ') group by 1 order by 2 desc;
   keyword    | count
--------------+-------
 >wallpaper<  |  1951
 > wallpaper< |    12
 >wallpaper < |     5
```

<em>That || operator is the SQL string concatenation operator, its used here to visually show the padding.</em>

Yup -- looks like there might be something to this -- [I asked Unsplash about it](https://github.com/unsplash/datasets/issues/13). There's a whole lot of text fields in the Unsplash data, and like I said, humans never enter data consistently. Turns out this is a known factor in this dataset and [they are are open to community input](https://github.com/unsplash/datasets/issues/13#issuecomment-672635482):

  > I believe that having clean fields is important. We might and will probably get to normalizing the location fields at some point in the future, it's just not really planned yet. I'll keep you and everyone posted on this issue as soon as we have a plan to tackle it
  >
  > Also, if anyone wants to give it a shot, we'd be happy to implement good solutions from the open-source community!
  >
  > -- @TimmyCarbone

That [issue is open](https://github.com/unsplash/datasets/issues/13) and there are a number of other text columns exhibiting the same characteristics as `unsplash_keywords.keyword`. It is being kept open for future reference.

### How about if the keywords are normalized on case?

```
unsplash_lite=# select count(*) from unsplash_keywords where keyword != lower(keyword);
 count
-------
     0
```

Okay - that looks good. Nothing to see here, move along.

### That 1 line difference on keywords from the import

When looking at the original `keywords.tsv000` file, it has 2,689,741 rows, which I assumed to be 1 header row and 2,689,740 data rows. When imported, postgresql reported 2,689,739 rows. This does not match my assumption. Lets double check and figure this out.

```sh
% wc -l keywords.tsv000
2689741 keywords.tsv000
```

```txt
unsplash_lite=# select count(*) from unsplash_keywords ;
  count
---------
 2689739
(1 row)
```

Still a row off, maybe there's an extra newline in `keywords.tsv000`?
```
% tail -2 keywords.tsv000
--2IBUMom1I     people  62.514862060546903              f
--2IBUMom1I     electronics     43.613410949707003              f
```

Nope. Well, maybe there was a row eliminated on import. In the [create_tables.sql](https://github.com/unsplash/datasets/blob/master/how-to/psql/create_tables.sql) the primary key on the `unsplash_keywords` table is a compound key of `photo_id` and `keyword`.

```sql
CREATE TABLE unsplash_keywords (
  photo_id varchar(11),
  keyword text,
  ai_service_1_confidence float,
  ai_service_2_confidence float,
  suggested_by_user boolean,
  PRIMARY KEY (photo_id, keyword)
);
```

How about reimporting this data file and see how it looks. Using a new table, that's just like the original one but without the primary key and then import the keywords tsv into it. The `\COPY` command here is adapted from [load-data-client.sql](https://github.com/unsplash/datasets/blob/master/how-to/psql/load-data-client.sql)

```txt
unsplash_light# CREATE TABLE unsplash_keywords_raw ( photo_id varchar(11), keyword text, ai_service_1_confidence float, ai_service_2_confidence float, suggested_by_user boolean
CREATE TABLE
unsplash_light# \COPY unsplash_keywords_raw FROM PROGRAM 'awk FNR-1 ./keywords.tsv* | cat' WITH ( FORMAT csv, DELIMITER E'\t', HEADER false);
COPY 2689739
```

No joy, same as before. Looks like its time to [write code](https://gist.github.com/copiousfreetime/ab23addcb3a6e5612a77d0724e5d52b9). The checks to do are:

* make sure that all the records have the same number of fields
* the number of records in the file matches that reported by `wc -l` and/or loaded by postgresl

My primary programming language is Ruby - so I'll use it.

```ruby
#!/usr/bin/env ruby

line_number    = 0
unique_counts  = Hash.new(0)
filename       = ARGV.shift
abort "filename needed" unless filename

File.open(filename) do |f|

  header          = f.readline.strip
  line_number     += 1
  header_parts    = header.split("\t")
  puts "Headers: #{header_parts.join(" -- ")}"

  f.each_line do |line|
    line_number += 1
    parts       = line.strip.split("\t")
    primary_key = parts[0..1].join("-")

    unique_counts[primary_key] += 1

    if parts.size != header_parts.size
      $stderr.puts "[#{line_number} - #{primary_key}] parts count #{parts.size} != #{header_parts.size}"
    end
  end
end

$stderr.puts "lines in file   : #{line_number}"
$stderr.puts "data lines      : #{line_number - 1}"
$stderr.puts "unique row count: #{unique_counts.size}"

unique_counts.each do |key, count|
  if count != 1
    $stderr.puts "Primary key #{key} has count #{count}"
  end
end


```

And then run it.

```txt
% ruby check-tsv.rb keywords.tsv000
Headers: photo_id -- keyword -- ai_service_1_confidence -- ai_service_2_confidence -- suggested_by_user
[1590611 - PF4s20KB678-"fujisan] parts count 2 != 5
[1590612 - mount fuji"-] parts count 4 != 5
lines in file   : 2689741
data lines      : 2689740
unique row count: 2689740
```

Looks like there is the row count that `wc -l` reported, but there are 2 rows, that are adjacent, with the wrong parts count. There is probably an embedded `\n` in the keyword field of photo `PF4s20KB678`. Lets dump those lines of the file.

```txt
% sed -n '1590610,1590613p' keywords.tsv000
PF4s20KB678     night   22.3271160125732                f
PF4s20KB678     "fujisan
mount fuji"                     t
PF4s20KB678     pier    22.6900939941406                f
```

Yup - definitely an embedded newline. And here is the difference between *record count* and *line count*. In this case my assumption that there was 1 line in the file per record was incorrect. One of the keywords has an embedded newline. Lets go check the database.

```sql
unsplash_lite=# select * from unsplash_keywords where photo_id = 'PF4s20KB678' and keyword like '%fujisan%';
  photo_id   |  keyword   | ai_service_1_confidence | ai_service_2_confidence | suggested_by_user
-------------+------------+-------------------------+-------------------------+-------------------
 PF4s20KB678 | fujisan   +|                         |                         | t
             | mount fuji |                         |                         |
(1 row)
```

Excellent! Assumption wrong! That's always a really good feeling. Looks like the import tool did the right thing and the data is consistent. Lets [notify Unsplash](https://github.com/unsplash/datasets/issues/29) and make sure that this is to be expected and documented appropriately. It is possible that other people using this dataset may parse it simply, like I did, and in doing so process the data incorrectly.

And the image in question is nice too :-)

<figure class="image">
  <img src="https://images.unsplash.com/photo-1588693273928-92fa26159c88?ixlib=rb-1.2.1&q=80&fm=jpg&crop=entropy&cs=tinysrgb&w=400&fit=max&ixid=eyJhcHBfaWQiOjE1ODI1Mn0" alt="fujisan mount fuji image by Tunafish Mayonnaise on Unsplash">
  <figcaption>
    Photo by <a href='https://unsplash.com/@tunamayoonigiri?utm_source=Try+Them+All&utm_medium=referral'>Tunafish Mayonnaise</a>
    on <a href="https://unsplash.com/?utm_source=Try+Them+all&utm_medium=referral">Unsplash</a>.
  </figcaption>
</figure>

## Conclusions

All in all - I got to be wrong, found some bugs, and cleared up some assumptions on the data. Now to remember the following things when processing the data later.

* make sure to strip leading and trailing whitespace on text fields - and convert empty strings to nulls
* possibly convert embedded newlines to spaces
* normalize case where appropriate
* expect nulls in fields

From a data quality perspective the Unsplash dataset is in pretty good shape, and they are quite receptive to feedback. I really appreciate Unsplash releasing this dataset and personally I want to help make it a fun and interesting data exploration.

In the next post I'll look at the data and see what interesting things might be in there. [Hit me up](https://twitter.com/copiousfreetime) if you have any questions for me, or to look for in the dataset.

enjoy!
