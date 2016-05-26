require 'elasticsearch'
require 'nokogiri'

ES_ITUNES_INDEX = 'itunes_tracks'.freeze

class ElasticsearchApi
  def initialize(options = {})
    options ||= {}
    options[:itunes_music_library_path] ||= './iTunes Music Library.xml'

    raise 'iTunes Music Library not found' unless File.exist?(options[:itunes_music_library_path])
    @options = options

    @client = Elasticsearch::Client.new log: true, host: 'localhost:9200'
  end

  def delete_index
    @client.indices.delete index: ES_ITUNES_INDEX
  end

  def search_track(track_id)
    results = @client.search index: ES_ITUNES_INDEX, body: {
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

  def index_itunes
    tracks = scan_itunes_xml_for_tracks

    fields = ['Track ID', 'Track Number', 'Year', 'Date Added', 'Play Count', 'Rating',
              'Name', 'Artist', 'Album Artist', 'Album', 'Genre', 'Location']
    content_fields = ['Track Number', 'Year', 'Name', 'Artist', 'Album Artist', 'Album', 'Genre']
    ignored_kinds = ['Ringtone', 'PDF document', 'Purchased MPEG-4 video file']

    tracks.each do |track|
      next if track['Track Type'] == 'Remote'
      next if ignored_kinds.include?(track['Kind']) || track['Kind'] =~ /(book|app)$/i
      next if track['Album'] =~ /Voice Memos/i

      track['Rating'] = 0 if track.key?('Rating Computed')

      body = track.select { |k, _v| fields.include?(k) }.merge(
        'content' => track.map { |k, v| content_fields.include?(k) ? v.to_s : nil }.compact.join(' ')
      )

      @client.index index: ES_ITUNES_INDEX, type: 'itunes_track', id: track['Track ID'], body: body
    end

    puts 'DONE.'
  end

  def create_mapping
    @client.indices.create index: ES_ITUNES_INDEX, body: {
      mappings: {
        itunes_track: {
          properties: {
            Album: {
              fields: {
                raw: {
                  index: 'not_analyzed',
                  type: 'string'
                }
              },
              type: 'string'
            },
            'Album Artist' => {
              fields: {
                raw: {
                  index: 'not_analyzed',
                  type: 'string'
                }
              },
              type: 'string'
            },
            Artist: {
              fields: {
                raw: {
                  index: 'not_analyzed',
                  type: 'string'
                }
              },
              type: 'string'
            },
            'Date Added' => {
              format: 'dateOptionalTime',
              type: 'date'
            },
            Genre: {
              fields: {
                raw: {
                  index: 'not_analyzed',
                  type: 'string'
                }
              },
              type: 'string'
            },
            Location: {
              type: 'string'
            },
            Name: {
              fields: {
                raw: {
                  index: 'not_analyzed',
                  type: 'string'
                }
              },
              type: 'string'
            },
            'Play Count' => {
              type: 'long'
            },
            Rating: {
              type: 'long'
            },
            'Track ID' => {
              type: 'long'
            },
            'Track Number' => {
              type: 'long'
            },
            Year: {
              type: 'long'
            },
            content: {
              type: 'string'
            }
          }
        }
      }
    }
  end

  private

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
          hash[last_key] = if child.text =~ /^\d+$/
                             child.text.to_i
                           else
                             child.text
                           end
        end
      end

      tracks << hash
    end
    tracks
  end
end
