# frozen_string_literal: true

class UrlFetcher
  YOUTUBE_PATTERNS = [
    %r{^https?://(?:www\.|m\.)?youtube\.com/(?:watch\?v=|embed/|v/)(?<id>[^&?/]+)},
    %r{^https?://youtu\.be/(?<id>[^&?/]+)},
    %r{^https?://(?:www\.|m\.)?youtube\.com/shorts/(?<id>[^&?/]+)},
    %r{^https?://music\.youtube\.com/watch\?v=(?<id>[^&?/]+)},
  ].freeze

  def youtube_url?(url)
    YOUTUBE_PATTERNS.any? { |pattern| url =~ pattern }
  end

  def youtube_video_id(url)
    YOUTUBE_PATTERNS.each do |pattern|
      match = url.match(pattern)
      return match[:id] if match
    end
    nil
  end

  def fetch_youtube_metadata(url)
    video_id = youtube_video_id(url)
    Rails.logger.debug { "Attempting to fetch YouTube metadata for URL: #{url}" }
    Rails.logger.debug { "Extracted video ID: #{video_id}" }
    return nil unless video_id

    begin
      Rails.logger.debug { "YouTube API Key: #{ENV['YOUTUBE_API_KEY'].present? ? 'Present' : 'Missing'}" }
      Rails.logger.debug 'Using YouTube API client...'

      response = YoutubeApi.client.list_videos('snippet', id: video_id)
      Rails.logger.debug { "Raw API Response: #{response.inspect}" }

      video = response.items.first
      if video.nil?
        Rails.logger.error "No video data returned from YouTube API for ID: #{video_id}"
        return fallback_metadata(url, video_id)
      end

      metadata = {
        title: "#{video.snippet.title} - YouTube",
        description: video.snippet.description.truncate(200),
        image: video.snippet.thumbnails.high.url,
        provider_name: determine_provider_name(url),
        provider_url: determine_provider_url(url),
      }

      Rails.logger.debug { "Generated metadata: #{metadata.inspect}" }
      metadata
    rescue => e
      Rails.logger.error "YouTube metadata fetch error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      fallback_metadata(url, video_id)
    end
  end

  private

  def determine_provider_name(url)
    if url.include?('music.youtube.com')
      'YouTube Music'
    else
      'YouTube'
    end
  end

  def determine_provider_url(url)
    if url.include?('music.youtube.com')
      'https://music.youtube.com'
    else
      'https://www.youtube.com'
    end
  end

  def fallback_metadata(url, video_id)
    thumbnail_url = "https://i.ytimg.com/vi/#{video_id}/hqdefault.jpg"
    {
      title: 'YouTube Video',
      description: url,
      image: thumbnail_url,
      provider_name: determine_provider_name(url),
      provider_url: determine_provider_url(url),
    }
  end

  # ...existing code...
end
