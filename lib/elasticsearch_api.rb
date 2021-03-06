require 'elasticsearch'
require 'nokogiri'

class ElasticsearchApi
  ES_ITUNES_INDEX = 'itunes'.freeze
  ES_FIELDS_MAPPING = {
    'Album' => {
      fields: {
        raw: {
          index: 'not_analyzed',
          type: 'string'
        }
      },
      'type' => 'string'
    },
    'Album Artist' => {
      fields: {
        raw: {
          index: 'not_analyzed',
          type: 'string'
        }
      },
      'type' => 'string'
    },
    'Artist' => {
      fields: {
        raw: {
          index: 'not_analyzed',
          type: 'string'
        }
      },
      'type' => 'string'
    },
    'Compilation' => {
      'type' => 'boolean'
    },
    'Date Added' => {
      'type' => 'date',
      'format' => 'dateOptionalTime'
    },
    'Disabled' => {
      'type' => 'boolean'
    },
    'Disc Count' => {
      'type' => 'long'
    },
    'Disc Number' => {
      'type' => 'long'
    },
    'File Folder Count' => {
      'type' => 'long'
    },
    'Genre' => {
      fields: {
        raw: {
          index: 'not_analyzed',
          type: 'string'
        }
      },
      'type' => 'string'
    },
    'Location' => {
      'type' => 'string'
    },
    'Name' => {
      fields: {
        raw: {
          index: 'not_analyzed',
          type: 'string'
        }
      },
      'type' => 'string'
    },
    'Play Count' => {
      'type' => 'long'
    },
    'Rating' => {
      'type' => 'long'
    },
    'Total Time' => {
      'type' => 'long'
    },
    'Track Count' => {
      'type' => 'long'
    },
    'Track ID' => {
      'type' => 'long'
    },
    'Track Number' => {
      'type' => 'long'
    },
    'Year' => {
      'type' => 'long'
    }
  }.freeze
  ES_FIELDS_LIST = ES_FIELDS_MAPPING.keys.freeze
  ES_CONTENT_FIELDS = ['Track Number', 'Year', 'Name', 'Artist', 'Album Artist', 'Album', 'Genre'].freeze

  def create_mapping
    @client.indices.create index: ES_ITUNES_INDEX, body: {
      mappings: {
        track: {
          properties: ES_FIELDS_MAPPING
        }
      }
    }
  end

  def delete_index
    @client.indices.delete index: ES_ITUNES_INDEX
  end

  def index_itunes_playlists
    playlists = scan_itunes_xml_for_playlists
    playlists.each do |playlist|
      next if playlist['Name'] == 'Library' && playlist['Master'] == true
      next if playlist['Name'] == 'Music' && playlist['Music'] == true
      next if playlist['Name'] == 'TV Shows' && playlist['TV Shows'] == true
      next if playlist['Name'] == 'Tones'
      next if playlist['Playlist Items'].nil?

      # top-level folder
      if playlist['Folder'] == true && playlist['Parent Persistent ID'].nil?
        playlist.delete 'Playlist Items'
      end

      unless playlist['Playlist Items'].nil?
        playlist['Tracks'] = get_tracks(playlist['Playlist Items'])
      end

      @client.index index: ES_ITUNES_INDEX, type: 'playlist', id: playlist['Playlist ID'], body: playlist
    end
  end

  def index_itunes_tracks
    tracks = scan_itunes_xml_for_tracks

    ignored_kinds = ['Ringtone', 'PDF document', 'Purchased MPEG-4 video file', 'Purchased AAC audio file']
    # Kind == 'MPEG audio file'

    tracks.each do |track|
      next if track['Track Type'] == 'Remote'
      next if ignored_kinds.include?(track['Kind']) || track['Kind'] =~ /(book|app)$/i
      next if track['Album'] =~ /Voice Memos/i

      track['Compilation'] = true if track.key?('Compilation')
      track['Disabled'] = true if track.key?('Disabled')
      track['Rating'] = 0 if track.key?('Rating Computed')

      body = track.select { |k, _v| ES_FIELDS_LIST.include?(k) }.merge(
        'content' => track.map { |k, v| ES_CONTENT_FIELDS.include?(k) ? v.to_s : nil }.compact.uniq.join(' ')
      )

      @client.index index: ES_ITUNES_INDEX, type: 'track', id: track['Track ID'], body: body
    end

    puts 'DONE.'
  end

  def initialize(options = {})
    options ||= {}
    options[:itunes_music_library_path] ||= './Library.xml'
    # options[:itunes_music_library_path] ||= './Library-partial.xml'

    raise 'iTunes Music Library not found' unless File.exist?(options[:itunes_music_library_path])
    @options = options

    @client = Elasticsearch::Client.new log: true, host: 'localhost:9200'
  end

  def process_itunes_playlists
    results = @client.search index: ES_ITUNES_INDEX, type: 'playlist', size: 10_000
    results['hits']['hits'].each do |result|
      tracks = get_tracks(result['_source']['Playlist Items'])
      result['_source']['Tracks'] = tracks
      @client.index index: ES_ITUNES_INDEX, type: 'playlist', id: result['_id'], body: result['_source']
    end
  end

  def get_tracks(track_ids)
    results = @client.search index: ES_ITUNES_INDEX, type: 'track', body: {
      query: {
        filtered: {
          filter: {
            terms: {
              _id: track_ids
            }
          }
        }
      },
      size: 10_000
    }
    if results['hits']['total'] > 10_000
      # TODO: finish this
      binding.pry
    end
    results['hits']['hits'].map { |hit| hit['_source'] }
  end

  def get_track(track_id)
    results = @client.search index: ES_ITUNES_INDEX, type: 'track', body: {
      query: {
        filtered: {
          filter: {
            term: {
              _id: track_id
            }
          }
        }
      },
      size: 1
    }
    begin
      results['hits']['hits'].first
    rescue
      nil
    end
  end

  private

  def scan_itunes_xml_for_playlists
    doc = Nokogiri::XML(File.open(@options[:itunes_music_library_path], 'r'))

    playlists = []
    doc.xpath('/plist/dict/array/dict').each do |node|
      hash = {}
      last_key = nil

      node.children.each do |child|
        next if child.blank?

        if child.name == 'key'
          last_key = child.text
        else
          if child.name == 'string'
            hash[last_key] = child.text
          elsif child.name == 'true'
            hash[last_key] = true
          elsif child.name == 'false'
            hash[last_key] = false
          elsif child.name == 'integer'
            hash[last_key] = child.text.to_i
          elsif child.name == 'array' && last_key == 'Playlist Items'
            hash[last_key] = child.text.scan(/Track ID\s*(\d*)/).flatten
          elsif child.name == 'data'
            # skip
          else
            raise "Not yet implemented: #{child.name}"
          end

        end
      end

      playlists << hash
    end
    playlists
  end

  def scan_itunes_xml_for_tracks
    doc = Nokogiri::XML(File.open(@options[:itunes_music_library_path], 'r'))

    tracks = []
    doc.xpath('/plist/dict/dict/dict').each do |node|
      hash = {}
      last_key = nil

      node.children.each do |child|
        next if child.blank?

        if child.name == 'key'
          last_key = child.text
        else
          if child.name == 'string' || child.name == 'date'
            hash[last_key] = child.text
          elsif child.name == 'true'
            hash[last_key] = true
          elsif child.name == 'false'
            hash[last_key] = false
          elsif child.name == 'integer'
            hash[last_key] = child.text.to_i
          else
            raise "Not yet implemented: #{child.name}"
          end

        end
      end

      tracks << hash
    end
    tracks
  end
end
