require 'pathname'
require 'rake/clean'

module GeoNamesInfo
  ROOT_URL     = "http://download.geonames.org/export/"
  PROJECT_ROOT = Pathname.new(__dir__).parent.parent
  DATA_DIR     = PROJECT_ROOT.join("data/geonames")

  DOWNLOADS = {
    "dump" =>  %w[
      readme.txt
      allCountries.zip
      cities500.zip
      cities1000.zip
      cities5000.zip
      cities15000.zip

      alternateNamesV2.zip

      admin1CodesASCII.txt
      admin2Codes.txt
      iso-languagecodes.txt
      featureCodes.txt
      timeZones.txt

      countryInfo.txt

      featureCodes_bg.txt
      featureCodes_en.txt
      featureCodes_nb.txt
      featureCodes_nn.txt
      featureCodes_no.txt
      featureCodes_ru.txt
      featureCodes_sv.txt

      userTags.zip
      hierarchy.zip
      adminCodes5.zip
      no-country.zip
    ],

    "zip" => %w[
      allCountries.zip
      readme.txt
      GB_full.csv.zip
      NL_full.csv.zip
    ]
  }
end

namespace :geonames do

  ## Create the individual file download tasks
  ##
  directory GeoNamesInfo::DATA_DIR
  local_files = []
  GeoNamesInfo::DOWNLOADS.map do |section, list|
    section_dir = GeoNamesInfo::DATA_DIR.join(section)
    directory section_dir.to_s

    list.each do |basename|
      remote_name = "#{section}/#{basename}"
      local_file  = section_dir.join(basename)
      local_files << local_file

      file local_file.to_s => section_dir do
        sh "curl -L #{GeoNamesInfo::ROOT_URL}#{remote_name} -# -o #{local_file}"
      end
    end
  end

  desc "Download all the data"
  task :download => local_files
  CLOBBER << local_files
end
__END__

tables = {
  'time_zones'      => 'data/dump/timeZones.clean.txt',
  'countries'       => 'data/dump/countryInfo.clean.txt',
  'languages'       => 'data/dump/iso-languagecodes.clean.txt',
  'features'        => 'data/dump/featureCodes_en.txt',
  'alternate_names' => 'data/dump/alternateNames.txt',
  'geonames'        => 'data/dump/allCountries.txt',
  'admin1_codes'    => 'data/dump/admin1CodesASCII.txt',
  'admin2_codes'    => 'data/dump/admin2Codes.txt',
  'postal_codes'    => 'data/zip/allCountries.txt',
  'hierarchy'       => 'data/dump/hierarchy.txt',
}

desc "Create Schema"
task :schema => :download do
  sh "psql --dbname #{DBNAME} --command 'CREATE SCHEMA IF NOT EXISTS #{DBSCHEMA}'"
end

#---------------------- Cleaning data -----------------------------------------
prepped_data = tables.values - %w[ data/dump/featureCodes_en.txt 
                                   data/dump/admin1CodesASCII.txt 
                                   data/dump/admin2Codes.txt
]

file 'data/dump/timeZones.clean.txt' => 'data/dump/timeZones.txt' do |t|
  sh "sed 1d < #{t.prerequisites.first} > #{t.name}"
end

file 'data/dump/countryInfo.clean.txt' => 'data/dump/countryInfo.txt' do |t|
  sh "grep -v '^#' < #{t.prerequisites.first} > #{t.name}"
end

file 'data/dump/iso-languagecodes.clean.txt' => 'data/dump/iso-languagecodes.txt' do |t|
  sh "sed 1d < #{t.prerequisites.first} > #{t.name}"
end

file 'data/dump/alternateNames.txt' => 'data/dump/alternateNames.zip' do |t|
  sh "unzip -o #{t.prerequisites.first} #{File.basename(t.name)} -d #{File.dirname(t.name)}"
  sh "touch #{t.name}"
end

file 'data/dump/allCountries.txt' => 'data/dump/allCountries.zip' do |t|
  sh "unzip -o #{t.prerequisites.first} #{File.basename(t.name)} -d #{File.dirname(t.name)}"
  sh "touch #{t.name}"
end

file 'data/zip/allCountries.txt' => 'data/zip/allCountries.zip' do |t|
  sh "unzip -o #{t.prerequisites.first} #{File.basename(t.name)} -d #{File.dirname(t.name)}"
  sh "touch #{t.name}"
end

file 'data/zip/hierarchy.txt' => 'data/zip/hierarchy.zip' do |t|
  sh "unzip -o #{t.prerequisites.first} #{File.basename(t.name)} -d #{File.dirname(t.name)}"
  sh "touch #{t.name}"
end

desc "Prepare the data"
task :prep =>  prepped_data

CLEAN << prepped_data

#---------------------- Importing data-----------------------------------------
def psql_file( fname, datafile = nil )
  cat = "cat #{fname}"
  if datafile then
    cat = "echo \"FROM '#{datafile}\' NULL AS ''\" | #{cat} -"
  end
  s = "#{cat} | psql --dbname #{DBNAME}"
  return s
end


desc "Import the data"
task :import => [:schema, :prep] do
  tables.each do |table, data_file|
    puts "==========> #{DBSCHEMA}.#{table} <==========="
    expanded_data_file_path = File.expand_path("#{data_file}")
    sh psql_file("ddl/create_#{table}.sql")

    puts ">> Checking if #{table} has rows......"
    has_data = %x[psql --dbname #{DBNAME} -t -c 'select count(*) from #{DBSCHEMA}.#{table}'].strip
    if has_data.to_i == 0 then
      puts ">> Importing data into #{DBNAME}.#{table}"
      sh psql_file("ddl/import_#{table}.sql", expanded_data_file_path)
      puts ">> Adjusting the data in #{DBNAME}.#{table}"
      sh psql_file("ddl/alter_#{table}.sql") if File.exist?( "ddl/alter_#{table}.sql" )
    else
      puts ">> #{table} has #{has_data} rows of data"
    end
  end
end

#---------------------- Indexing data-----------------------------------------
desc "Create Indexes and Constraints"
task :index => :import do
  puts ">> Applying indexes"
  sh psql_file("ddl/index_tables.sql")
end

desc "Do the whole thing"
task :default => :index

#---------------------- Post cleanup -----------------------------------------

# vaccuum analyze all the tables we just created
desc "Post process"
task :post do
  tables.each do |table, _|
    full_name = "#{DBSCHEMA}.#{table}"
    puts "Vaccuming / analyzing #{full_name}"
    sh "psql --dbname #{DBNAME} --command 'VACUUM VERBOSE ANALYZE #{full_name}'"
  end
end

#---------------------- Drop it all -----------------------------------------
desc "Drop the tables"
task :drop do
  sh "psql --dbname #{DBNAME} --command 'DROP SCHEMA IF EXISTS #{DBSCHEMA} CASCADE'"
end
