class RaarClient

  JSON_API_CONTENT_TYPE = 'application/vnd.api+json'.freeze
  LATEST_RAAR_TRACK_PATH = 'tracks?sort=-started_at&page[size]=1'.freeze

  attr_reader :settings, :logger

  def initialize(settings, logger)
    @settings = settings
    @logger = logger
  end

  def fetch_latest_track
    response = raar_request(:get,
                            LATEST_RAAR_TRACK_PATH,
                            params: { api_token: api_token },
                            accept: JSON_API_CONTENT_TYPE)
    json = JSON.parse(response.body)
    json['data'].first
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

  private

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
      username: settings['username'],
      password: settings['password']
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
        url: "#{settings['url']}/#{path}",
        headers: headers
      )
    )
  end

  def raar_http_options
    @raar_http_options ||=
      (settings['options'] || {})
      .each_with_object({}) do |(key, val), hash|
        hash[key.to_sym] = val
      end
  end

end
