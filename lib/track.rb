class Track

  attr_accessor :title, :artist, :started_at, :finished_at

  def initialize(attributes = {})
    attributes.each do |key, value|
      send("#{key}=", value)
    end
  end

  def attributes
    {
      title: title,
      artist: artist,
      started_at: started_at,
      finished_at: finished_at
    }
  end

  def same?(other)
    similar_key?(other, :title) &&
      similar_key?(other, :artist)
  end

  def duration
    finished_at - started_at
  end

  private

  def similar_key?(other, key)
    send(key).to_s.downcase.strip == other.send(key).to_s.downcase.strip
  end

end
