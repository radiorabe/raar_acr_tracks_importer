class AcrClient

  attr_reader :settings

  def initialize(settings)
    @settings = settings
  end

  def fetch_tracks(date)
    body = fetch(date).to_s
    JSON
      .parse(body)
      .map { |e| build_track(e) }
      .compact
      .sort_by { |t| [t.started_at, t.finished_at] }
  end

  def find_first_date_ever(initial = Date.today, step = 32)
    date = initial
    body = nil
    while body.to_s != '[]'
      date -= step
      body = fetch(date)
    end
    narrow_search_dates(date, step)
  rescue RestClient::InternalServerError
    # first ACR response on date without entries is 500, second []
    narrow_search_dates(date, step)
  end

  private

  def narrow_search_dates(date, step)
    if step == 1
      date + 1
    else
      find_first_date_ever(date + step, step / 2)
    end
  end

  def build_track(entry)
    metadata = entry['metadata']
    return if !metadata || !metadata['music']

    Track.new(track_attrs(metadata))
  end

  def track_attrs(metadata)
    music = metadata['music'].first
    artists = music['artists']
    time = Time.parse("#{metadata['timestamp_utc']} UTC")
    {
      title: music['title'],
      artist: artists ? artists.map { |a| a['name'] }.uniq.join(', ') : nil,
      started_at: time,
      finished_at: time + metadata['played_duration']
    }
  end

  def fetch(date)
    RestClient.get(url(date))
  end

  def url(date)
    url = settings['url']
    key = settings['access_key']
    "#{url}?access_key=#{key}&date=#{date.strftime('%Y%m%d')}"
  end

end
