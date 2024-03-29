require 'yaml'
require 'json'

require_relative 'track'
require_relative 'raar_client'
require_relative 'acr_client'

class Importer

  def run
    import_latest(date_to_import_from)
  rescue Exception => e # rubocop:disable Lint/RescueException
    logger.fatal("#{e}\n#{e.backtrace.join("\n")}")
  end

  private

  def date_to_import_from
    latest_track = raar_client.fetch_latest_track
    if latest_track
      Time.parse(latest_track['attributes']['started_at'])
    else
      acr_client.find_first_date_ever.to_time
    end
  end

  def import_latest(since)
    logger.info("Importing all tracks since #{since}")
    (since.getutc.to_date..Date.today).each do |date|
      import_tracks(date, since)
    end
  end

  def import_tracks(date, since)
    tracks = acr_client.fetch_tracks(date)
    imported_count = 0
    iterate_without_duplicates(tracks) do |track|
      if track.started_at > since && track.duration > minimum_duration
        raar_client.create_track(track.attributes)
        imported_count += 1
      end
    end
    logger.info("Imported #{imported_count} of #{tracks.size} " \
                "tracks for #{date}")
  end

  def iterate_without_duplicates(tracks)
    tracks.each do |current|
      yield @previous_track if @previous_track && assert_no_duplicate(@previous_track, current)
      @previous_track = current
    end
  end

  def assert_no_duplicate(previous, current)
    if previous.same?(current)
      # Ignore duplicates
      current.started_at = previous.started_at
      logger.debug("Ignoring duplicate track #{current.title} " \
                   "at #{current.started_at}")
      false
    else
      assert_no_overlapping(previous, current)
      # Only process non-zero length tracks
      previous.started_at < previous.finished_at
    end
  end

  def assert_no_overlapping(previous, current)
    # previous overlaps into current => set previous finished_at earlier
    if current.started_at < previous.finished_at
      logger.debug("Trim overlapping track #{previous.title} at " \
                   "#{current.started_at} for " \
                   "#{(previous.finished_at - current.started_at).round}s")
      previous.finished_at = current.started_at
    end
  end

  def minimum_duration
    settings['importer']['minimum_duration'] || 0
  end

  def acr_client
    @acr_client ||= AcrClient.new(settings['acr'])
  end

  def raar_client
    @raar_client ||= RaarClient.new(settings['raar'], logger)
  end

  def settings
    @settings ||= YAML.safe_load(File.read(settings_file))
  end

  def settings_file
    File.join(File.join(__dir__), '..', 'config', 'settings.yml')
  end

  def logger
    @logger ||= create_logger.tap do |logger|
      level = settings['importer']['log_level'] || 'info'
      logger.level = Logger.const_get(level.upcase)
    end
  end

  def create_logger
    if settings['importer']['log'] == 'syslog'
      require 'syslog/logger'
      Syslog::Logger.new('raar-acr-tracks-importer').tap do |logger|
        logger.formatter = proc { |severity, _datetime, _prog, msg|
          "#{Logger::SEV_LABEL[severity]} #{msg}"
        }
      end
    else
      Logger.new($stdout)
    end
  end

end
