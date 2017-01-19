#!/usr/bin/env ruby

require 'optparse'
require 'pry'

$LOAD_PATH << File.dirname(__FILE__) + '/lib'
require 'elasticsearch_api'

options = {}
OptionParser.new do |opts|
  opts.on('--delete-index', 'Delete index') do |_v|
    options[:action] = :delete_index
  end

  opts.on('--create-mapping', 'Create index mapping') do |_v|
    options[:action] = :create_mapping
  end

  opts.on('--index-tracks', 'Index iTunes Track') do |_v|
    options[:action] = :index_itunes_tracks
  end

  opts.on('--index-playlists', 'Index iTunes Playlists') do |_v|
    options[:action] = :index_itunes_playlists
  end
end.parse!

raise 'Nothing to do!' if options[:action].nil?

elasticsearch_api = ElasticsearchApi.new
elasticsearch_api.send options[:action]
