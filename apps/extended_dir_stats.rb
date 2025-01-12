#!/usr/bin/env ruby

# Shows stats in this format:

# Statistics for directory: /home/user/data
# Total files: 4169
# Total directories: 473
# Total size: 299319283 bytes

# File size ranges:
# 1KB: 486 below, 3683 above
# 10KB: 2026 below, 2143 above
# 100KB: 3516 below, 653 above
# 1MB: 4137 below, 32 above
# 10MB: 4169 below, 0 above
# 100MB: 4169 below, 0 above
# 1GB: 4169 below, 0 above

# Directory size ranges:
# 1KB: 121 below, 352 above
# 10KB: 148 below, 325 above
# 100KB: 271 below, 202 above
# 1MB: 403 below, 70 above
# 10MB: 470 below, 3 above
# 100MB: 472 below, 1 above
# 1GB: 473 below, 0 above

# Пример вызова
# extended_dir_stats /home/user/data

require 'find'
require 'gtk3'

SIZE_RANGES = {
  "1KB" => 1024,
  "10KB" => 10240,
  "100KB" => 102400,
  "1MB" => 1024 * 1024,
  "10MB" => 10 * 1024 * 1024,
  "100MB" => 100 * 1024 * 1024,
  "1GB" => 1024 * 1024 * 1024
}

stats = {
  file_count: 0,
  dir_count: 0,
  file_size_ranges: {},
  dir_size_ranges: {},
  total_size: 0
}

SIZE_RANGES.each do |range, _|
  stats[:file_size_ranges][range] = [0, 0]
  stats[:dir_size_ranges][range] = [0, 0]
end

def categorize_size(size)
  SIZE_RANGES.each do |range, limit|
    if size <= limit
      return range, :below
    end
  end
  return SIZE_RANGES.keys.last, :above
end

def update_stats(stats, type, size)
  SIZE_RANGES.each do |range, limit|
    if size <= limit
      stats["#{type}_size_ranges".to_sym][range][0] += 1
    else
      stats["#{type}_size_ranges".to_sym][range][1] += 1
    end
  end
end

if ARGV.empty?
  puts "Usage: ruby script.rb <directory>"
  exit
end

directory = ARGV[0]

unless Dir.exist?(directory)
  puts "Directory not found: #{directory}"
  exit
end

# Traverse the directory
Find.find(directory) do |path|
  next if File.symlink?(path)

  if File.directory?(path)
    stats[:dir_count] += 1
    dir_size = Dir.glob(File.join(path, '**', '*')).select { |f| File.file?(f) }.map { |f| File.size(f) }.sum
    update_stats(stats, :dir, dir_size)
  else
    stats[:file_count] += 1    
    file_size = File.size(path)
    stats[:total_size] += file_size
    update_stats(stats, :file, file_size)
  end
rescue Errno::EACCES
  next
end

# Prepare the statistics text
stats_text = <<-TEXT
Statistics for directory: #{directory}
Total files: #{stats[:file_count]}
Total directories: #{stats[:dir_count]}
Total size: #{stats[:total_size]} bytes

File size ranges:
TEXT

stats[:file_size_ranges].each do |range, counts|
  stats_text += "#{range}: #{counts[0]} below, #{counts[1]} above\n"
end

stats_text += "\nDirectory size ranges:\n"

stats[:dir_size_ranges].each do |range, counts|
  stats_text += "#{range}: #{counts[0]} below, #{counts[1]} above\n"
end

Gtk.init

window = Gtk::Window.new("Directory Statistics")
window.set_size_request(400, 600)
window.signal_connect("destroy") { Gtk.main_quit }

vbox = Gtk::Box.new(:vertical, 10)
vbox.set_homogeneous(false)

label = Gtk::Label.new("Statistics for directory: #{directory}")
vbox.pack_start(label, expand: false, fill: false, padding: 10)

text_view = Gtk::TextView.new
text_view.buffer.text = stats_text
text_view.editable = false
text_view.wrap_mode = Gtk::WrapMode::WORD

scrolled_window = Gtk::ScrolledWindow.new
scrolled_window.set_policy(Gtk::PolicyType::AUTOMATIC, Gtk::PolicyType::AUTOMATIC)
scrolled_window.add(text_view)

vbox.pack_start(scrolled_window, expand: true, fill: true, padding: 10)

window.add(vbox)
window.show_all

Gtk.main
