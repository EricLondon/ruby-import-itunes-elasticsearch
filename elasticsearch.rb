#!/usr/bin/env ruby

require 'optparse'

$LOAD_PATH << File.dirname(__FILE__) + '/lib'
require 'elasticsearch_api'

options = {}
OptionParser.new do |opts|

  opts.on("--delete-index", "Delete index") do |v|
    options[:action] = :delete_index
  end

  opts.on("--create-mapping", "Create index mapping") do |v|
    options[:action] = :create_mapping
  end

  opts.on("--index", "Index iTunes") do |v|
    options[:action] = :index_itunes
  end

end.parse!

raise 'Nothing to do!' if options[:action].nil?

elasticsearch_api = ElasticsearchApi.new
elasticsearch_api.send options[:action]
