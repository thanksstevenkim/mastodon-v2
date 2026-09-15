# frozen_string_literal: true

module OAuthApplicationNameBlocklist
  module_function

  def blocked?(name)
    candidate = name.to_s.strip
    return false if candidate.empty?

    blocked_names.any? do |blocked_name|
      blocked_name.casecmp?(candidate)
    end
  end

  def blocked_names
    ENV.fetch('BLOCKED_OAUTH_APP_NAMES', '')
      .split(',')
      .map(&:strip)
      .reject(&:empty?)
  end
end
