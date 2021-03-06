require 'tmpdir'
require 'equivalent-xml/rspec_matchers'
require 'byebug'
require 'simplecov'
require 'coveralls'

SimpleCov.formatter = Coveralls::SimpleCov::Formatter
SimpleCov.start do
  track_files "bin/**/*"
  track_files "devel/**/*.rb"
  add_filter "spec/**/*.rb"
end

puts "running in #{ENV['ROBOT_ENVIRONMENT']} mode"
bootfile = File.expand_path(File.dirname(__FILE__) + '/../config/boot')
require bootfile

tmp_output_dir = File.join(PRE_ASSEMBLY_ROOT, 'tmp')
FileUtils.mkdir_p tmp_output_dir

def noko_doc(x)
  Nokogiri.XML(x) { |conf| conf.default_xml.noblanks }
end
