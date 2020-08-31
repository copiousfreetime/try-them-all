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



