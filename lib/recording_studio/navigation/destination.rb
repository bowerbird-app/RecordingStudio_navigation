# frozen_string_literal: true

module RecordingStudio
  module Navigation
    # The canonical record a host reads back. Frozen after registration:
    # presentation overrides belong to the host, not to this value.
    #
    # `sensitivity` is advisory metadata for hosts that want to treat some
    # destinations more carefully. It is not authorization, and this class
    # deliberately has no method that answers whether anyone may see the
    # destination. Recording Studio Accessible and the host own access control.
    class Destination
      SENSITIVITIES = %i[normal sensitive restricted].freeze

      attr_reader :key, :label, :description, :route, :icon, :tags, :groups, :sensitivity

      def self.validated_sensitivity(sensitivity, attribute: :sensitivity)
        value = sensitivity.is_a?(String) ? sensitivity.to_sym : sensitivity
        return value if SENSITIVITIES.include?(value)

        raise InvalidDestinationError.for(
          attribute, sensitivity, "must be one of #{SENSITIVITIES.map(&:inspect).join(', ')}"
        )
      end

      def initialize(key:, label:, route:, description: "", icon: nil, tags: [], groups: [], sensitivity: :normal)
        @key = required_string(key, :key)
        @label = required_string(label, :label)
        @description = optional_string(description, :description) || ""
        @route = validated_route(route)
        @icon = optional_string(icon, :icon)
        @tags = symbol_set(tags, :tags)
        @groups = symbol_set(groups, :groups)
        @sensitivity = self.class.validated_sensitivity(sensitivity)

        freeze
      end

      def ==(other)
        return false unless other.is_a?(Destination)

        canonical_state == other.canonical_state
      end
      alias eql? ==

      def hash
        [self.class, *canonical_state].hash
      end

      protected

      def canonical_state
        [key, label, description, route, icon, tags, groups, sensitivity]
      end

      private

      def required_string(value, attribute)
        string = value.is_a?(Symbol) ? value.to_s : value
        raise InvalidDestinationError.for(attribute, value, "must be a non-empty String") unless
          string.is_a?(String) && !string.strip.empty?

        string.dup.freeze
      end

      def optional_string(value, attribute)
        return nil if value.nil?

        string = value.is_a?(Symbol) ? value.to_s : value
        raise InvalidDestinationError.for(attribute, value, "must be a String when present") unless string.is_a?(String)

        string.dup.freeze
      end

      def validated_route(route)
        return route if route.is_a?(Route)

        raise InvalidDestinationError.for(:route, route, "must be a #{Route}")
      end

      def symbol_set(values, attribute)
        raise InvalidDestinationError.for(attribute, values, "must be a collection") unless
          values.is_a?(Enumerable) && !values.is_a?(Hash)

        Set.new(values.map { |value| symbol_member(value, attribute) }).freeze
      end

      def symbol_member(value, attribute)
        raise InvalidDestinationError.for(attribute, value, "entries must be Symbols or Strings") unless
          value.is_a?(Symbol) || value.is_a?(String)
        raise InvalidDestinationError.for(attribute, value, "entries cannot be blank") if value.to_s.strip.empty?

        value.to_sym
      end
    end
  end
end
