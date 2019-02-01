#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)
require 'yaml'
require 'json'

class RaarAcrTracksImporter

  JSON_API_CONTENT_TYPE = 'application/vnd.api+json'.freeze

  LATEST_RAAR_TRACK_PATH = 'tracks?sort=-started_at&page[size]=1'.freeze

  def run
    latest_track = fetch_raar_latest_track
    if latest_track
      import_latest(Time.parse(latest_track['attributes']['started_at']))
    else
      import_all_time
    end
  end

  private

  def fetch_raar_latest_track
    response = raar_request(:get,
                            LATEST_RAAR_TRACK_PATH,
                            params: { api_token: api_token },
                            accept: JSON_API_CONTENT_TYPE)
    json = JSON.parse(response.body)
    json['data'].first
  end

  def import_latest(since)
    (since.to_date..Date.today).each do |date|
      import_tracks(date, since)
    end
  end

  def import_all_time
    date = Date.today
    date -= 1 while import_tracks(date)
  end

  def import_tracks(date, since = nil)
    each_acr_track(date) do |track|
      create_track(track) if !since || track[:started_at] > since
    end
  end

  def each_acr_track(date, &block)
    data = fetch_from_acr(date)
    if data.is_a?(Array)
      iterate_without_duplicates(data, &block)
      true
    elsif data.is_a?(Hash) && json['status'] == 500
      false
    else
      raise("Unexpected JSON data #{data.class}")
    end
  end

  def iterate_without_duplicates(data)
    previous = nil
    data.each do |entry|
      current = convert_track(entry)
      yield previous if previous && assert_no_duplicate(previous, current)
      previous = current
    end
  end

  def assert_no_duplicate(previous, current)
    if same_track?(previous, current)
      # Ignore duplicates
      current[:started_at] = previous[:started_at]
      false
    else
      assert_no_overlapping(previous, current)
      # Only process non-zero length tracks
      previous[:started_at] < previous[:finished_at]
    end
  end

  def assert_no_overlapping(previous, current)
    # previous overlaps into current => set previous finished_at earlier
    if current[:started_at] < previous[:finished_at]
      previous[:finished_at] = current[:started_at]
    end
  end

  def convert_track(entry)
    metadata = entry['metadata']
    music = metadata['music'].first
    artists = music['artists']
    time = Time.parse(metadata['timestamp_utc'] + ' UTC')
    {
      title: music['title'],
      artist: artists ? artists.map { |a| a['name'] }.uniq.join(', ') : nil,
      started_at: time,
      finished_at: time + metadata['played_duration']
    }
  end

  def same_track?(one, other)
    similar_key?(one, other, :title) &&
      similar_key?(one, other, :artist)
  end

  def similar_key?(one, other, key)
    one[key].to_s.downcase.strip == other[key].to_s.downcase.strip
  end

  def create_track(track)
    raar_request(:post,
                 'tracks',
                 create_payload(track).to_json,
                 content_type: JSON_API_CONTENT_TYPE,
                 accept: JSON_API_CONTENT_TYPE)
  rescue RestClient::UnprocessableEntity => e
    puts e.response.to_s
    raise e
  end

  def create_payload(track)
    {
      api_token: api_token,
      data: {
        type: 'track',
        attributes: track
      }
    }
  end

  def api_token
    @api_token ||= login_raar_user['api_token']
  end

  def login_raar_user
    credentials = {
      username: settings['raar']['username'],
      password: settings['raar']['password']
    }
    response = raar_request(:post, 'login', credentials)
    json = JSON.parse(response.body)
    json['data']['attributes']
  end

  def raar_request(method, path, payload = nil, headers = {})
    RestClient::Request.execute(
      raar_http_options.merge(
        method: method,
        payload: payload,
        url: "#{raar_url}/#{path}",
        headers: headers
      )
    )
  end

  def fetch_from_acr(date)
    body = RestClient.get(acr_url(date)).to_s
    JSON.parse(body)
  end

  def raar_http_options
    @raar_http_options ||=
      (settings['raar']['options'] || {})
      .each_with_object({}) do |(key, val), hash|
        hash[key.to_sym] = val
      end
  end

  def acr_url(date)
    url = settings['acr']['url']
    key = settings['acr']['access_key']
    "#{url}?access_key=#{key}&date=#{date.strftime('%Y%m%d')}"
  end

  def raar_url
    settings['raar']['url']
  end

  def settings
    @settings ||= YAML.safe_load(File.read(settings_file))
  end

  def settings_file
    File.join(home, 'config', 'settings.yml')
  end

  def home
    File.join(__dir__)
  end

end

RaarAcrTracksImporter.new.run
