# frozen_string_literal: true

module SignupReasonBlocklist
  module_function

  def blocked?(reason)
    candidate = reason.to_s.strip
    return false if candidate.empty?

    blocked_reasons.any? do |blocked_reason|
      blocked_reason.casecmp?(candidate)
    end
  end

  def blocked_reasons
    ENV.fetch('BLOCKED_SIGNUP_REASONS', '')
      .split(',')
      .map(&:strip)
      .reject(&:empty?)
  end
end
