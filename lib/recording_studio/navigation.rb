# frozen_string_literal: true

require "recording_studio/navigation/errors"
require "recording_studio/navigation/route"
require "recording_studio/navigation/destination"
require "recording_studio/navigation/registry"

module RecordingStudio
  # Shared registry of navigable destinations.
  #
  # Gems declare where they can be reached; hosts decide what to show. Nothing
  # here renders a menu, touches the database, or makes an access decision.
  module Navigation
    class << self
      # Declare one destination. Returns the canonical Destination. Declaring
      # the same definition again returns the object already registered, so a
      # re-run of an initializer or a reloaded require cannot duplicate it.
      def register(key:, label:, route:, description: "", icon: nil, tags: [], groups: [], sensitivity: :normal)
        destination = Destination.new(
          key: key, label: label, route: Route.coerce(route), description: description,
          icon: icon, tags: tags, groups: groups, sensitivity: sensitivity
        )
        location = caller_locations(1, 1)&.first
        source = "#{location.path}:#{location.lineno}" if location

        registry.add(destination, source: source)
      end

      # Registered destinations in registration order, optionally narrowed by
      # one tag and/or one sensitivity.
      def destinations(tag: nil, sensitivity: nil)
        registry.destinations(DestinationFilter.new(tag: tag, sensitivity: sensitivity))
      end

      # Destinations a gem placed in one named group. An unknown group is empty.
      def group(name)
        registry.group(group_name(name))
      end

      # Case-insensitive substring match over key, label, description, and tag
      # names. A blank query returns the filtered list.
      def search(query, tag: nil, sensitivity: nil)
        registry.search(query, DestinationFilter.new(tag: tag, sensitivity: sensitivity))
      end

      private

      def registry
        @registry ||= Registry.new
      end

      def group_name(name)
        raise InvalidDestinationError.for(:group, name, "must be a Symbol or String") unless
          name.is_a?(Symbol) || name.is_a?(String)

        name.to_sym
      end
    end
  end
end
