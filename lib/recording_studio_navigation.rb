# frozen_string_literal: true

require "recording_studio"
require "recording_studio/navigation"
require "recording_studio_navigation/version"
require "recording_studio_navigation/engine"
require "recording_studio_navigation/configuration"
require "recording_studio_navigation/capabilities/example"

module RecordingStudioNavigation
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end
  end
end
