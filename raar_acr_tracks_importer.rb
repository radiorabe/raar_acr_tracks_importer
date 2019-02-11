#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)
require 'yaml'
require 'json'
require 'syslog/logger'

class RaarAcrTracksImporter

  JSON_API_CONTENT_TYPE = 'application/vnd.api+json'.freeze

  LATEST_RAAR_TRACK_PATH = 'tracks?sort=-started_at&page[size]=1'.freeze

  def run
    import_latest(date_to_import_from)
  rescue StandardError => e
    logger.fatal("#{e}\n#{e.backtrace.join("\n")}")
  end

  private

  def date_to_import_from
    latest_track = fetch_raar_latest_track
    if latest_track
      Time.parse(latest_track['attributes']['started_at'])
    else
      find_first_date_ever.to_time
    end
  end

  def fetch_raar_latest_track
    response = raar_request(:get,
                            LATEST_RAAR_TRACK_PATH,
                            params: { api_token: api_token },
                            accept: JSON_API_CONTENT_TYPE)
    json = JSON.parse(response.body)
    json['data'].first
  end

  def import_latest(since)
    logger.info("Importing all tracks since #{since}")
    (since.to_date..today).each do |date|
      import_tracks(date, since)
    end
  end

  def find_first_date_ever(initial = today, step = 32)
    date = initial
    body = nil
    while body.to_s != '[]'
      date -= step
      body = fetch_from_acr(date)
    end
    narrow_search_dates(date, step)
  rescue RestClient::InternalServerError
    # first ACR response on date without entries is 500, second []
    narrow_search_dates(date, step)
  end

  def narrow_search_dates(date, step)
    if step == 1
      date + 1
    else
      find_first_date_ever(date + step, step / 2)
    end
  end

  def import_tracks(date, since)
    data = fetch_json_from_acr(date)
    imported_count = 0
    iterate_without_duplicates(data) do |track|
      if track[:started_at] > since
        create_track(track)
        imported_count += 1
      end
    end
    logger.info("Imported #{imported_count} of #{data.size} tracks for #{date}")
  end

  def iterate_without_duplicates(data)
    data.each do |entry|
      current = convert_track(entry)
      if @previous_track && assert_no_duplicate(@previous_track, current)
        yield @previous_track
      end
      @previous_track = current
    end
  end

  def assert_no_duplicate(previous, current)
    if same_track?(previous, current)
      # Ignore duplicates
      current[:started_at] = previous[:started_at]
      logger.debug("Ignoring duplicate track #{current[:title]}" \
                   " at #{current[:started_at]}")
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
      logger.debug("Trim overlapping track #{previous[:title]} at " \
                  "#{current[:started_at]} for " \
                  "#{(previous[:finished_at] - current[:started_at]).round}s")
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
    logger.error("Could not create track #{track.inspect}:\n#{e.response}")
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

  def raar_url
    settings['raar']['url']
  end

  def raar_http_options
    @raar_http_options ||=
      (settings['raar']['options'] || {})
      .each_with_object({}) do |(key, val), hash|
        hash[key.to_sym] = val
      end
  end

  def fetch_json_from_acr(date)
    body = fetch_from_acr(date).to_s
    JSON.parse(body).sort_by do |e|
      [e['metadata']['timestamp_utc'], e['metadata']['played_duration']]
    end
  end

  def fetch_from_acr(date)
    RestClient.get(acr_url(date))
  end

  def acr_url(date)
    url = settings['acr']['url']
    key = settings['acr']['access_key']
    "#{url}?access_key=#{key}&date=#{date.strftime('%Y%m%d')}"
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

  def today
    @today ||= Date.today
  end

  def logger
    # Syslog::Logger.new('raar-acr-tracks-importer')
    # Logger.new(STDOUT)
    @logger ||= Syslog::Logger.new('raar-acr-tracks-importer').tap do |logger|
      logger.level = Logger::INFO
    end
  end

end

RaarAcrTracksImporter.new.run
