# frozen_string_literal: true

module RecordingStudio
  module Navigation
    # Base class for invalid or conflicting destination declarations.
    class ConfigurationError < StandardError; end

    # Raised when registration or query data cannot form a valid value.
    class InvalidDestinationError < ConfigurationError
      attr_reader :attribute, :value

      def self.for(attribute, value, requirement)
        new("#{attribute} #{requirement} (got #{value.inspect})", attribute: attribute, value: value)
      end

      def initialize(message, attribute:, value:)
        @attribute = attribute
        @value = value
        super(message)
      end
    end

    # Raised only when a key already belongs to a different definition.
    # Registering the same definition again is idempotent.
    class DuplicateDestinationError < ConfigurationError
      attr_reader :key, :existing, :attempted, :existing_source, :attempted_source

      def initialize(key:, existing:, attempted:, existing_source: nil, attempted_source: nil)
        @key = key
        @existing = existing
        @attempted = attempted
        @existing_source = existing_source
        @attempted_source = attempted_source

        super(
          "Navigation destination #{key.inspect} is already registered with a different definition. " \
          "Registered at #{existing_source || 'an unknown location'}, " \
          "re-registered at #{attempted_source || 'an unknown location'}."
        )
      end
    end

    # Raised at request time when a route cannot be resolved in the current
    # application's route set.
    class RouteResolutionError < StandardError; end
  end
end
