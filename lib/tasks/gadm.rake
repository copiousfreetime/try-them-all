require 'pathname'
require 'rake/clean'

module GadmInfo
  ZIP_BASENAME = "gadm36_gpkg.zip"
  DB_BASENAME  = "gadm36.gpkg"
  SRC_URL      = "https://biogeo.ucdavis.edu/data/gadm3.6/#{ZIP_BASENAME}"
  PROJECT_ROOT = Pathname.new(__dir__).parent.parent
  DATA_DIR     = PROJECT_ROOT.join("data/gadm")
  DEST_ZIP     = DATA_DIR.join(ZIP_BASENAME)
  DEST_DB      = DATA_DIR.join(DB_BASENAME)
end

namespace :gadm do

  directory GadmInfo::DATA_DIR
  file GadmInfo::DEST_ZIP.to_s => GadmInfo::DATA_DIR do
    sh "curl -L #{GadmInfo::SRC_URL} -# -o #{GadmInfo::DEST_ZIP}"
  end

  file GadmInfo::DEST_DB.to_s => GadmInfo::DEST_ZIP do |t|
    sh "unzip -d #{GadmInfo::DATA_DIR} -o #{GadmInfo::DEST_ZIP}"
    touch t.name
  end

  desc "Download all the data"
  task :download => GadmInfo::DEST_DB

  CLOBBER << GadmInfo::DEST_ZIP.to_s
  CLOBBER << GadmInfo::DEST_DB.to_s

end
