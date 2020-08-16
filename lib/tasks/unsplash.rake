require 'pathname'
require 'rake/clean'

module UnsplashInfo
  ZIP_BASENAME = "unsplash-research-dataset-lite-latest.zip"
  SRC_URL      = "https://unsplash.com/data/lite/latest"
  PROJECT_ROOT = Pathname.new(__dir__).parent.parent
  DATA_DIR     = PROJECT_ROOT.join("data/unsplash")
  DEST_ZIP     = DATA_DIR.join(ZIP_BASENAME)

  DATA_FILES = %w[
    README.md
    photos.tsv000
    collections.tsv000
    keywords.tsv000
    conversions.tsv000
  ]

end

namespace :unsplash do

  directory UnsplashInfo::DATA_DIR
  local_files = []

  file UnsplashInfo::DEST_ZIP.to_s => UnsplashInfo::DATA_DIR do
    sh "curl -L #{UnsplashInfo::SRC_URL} -# -o #{UnsplashInfo::DEST_ZIP}"
  end

  UnsplashInfo::DATA_FILES.each do |basename|
    local_file = UnsplashInfo::DATA_DIR.join(basename)
    local_files << local_file.to_s

    file local_file.to_s => UnsplashInfo::DEST_ZIP do |t|
      sh "unzip -d #{UnsplashInfo::DATA_DIR} -o -D #{UnsplashInfo::DEST_ZIP} #{local_file.basename}"
      touch t.name
    end
  end

  desc "Download all the data"
  task :download => local_files

end
