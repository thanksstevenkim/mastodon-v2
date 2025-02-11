# frozen_string_literal: true

require 'google/apis/youtube_v3'

module YoutubeApi
  def self.client
    @client ||= Google::Apis::YoutubeV3::YouTubeService.new.tap do |client|
      client.key = ENV.fetch('YOUTUBE_API_KEY', nil)
    end
  end
end
