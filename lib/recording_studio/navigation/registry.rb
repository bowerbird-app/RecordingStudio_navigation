# frozen_string_literal: true

module RecordingStudio
  module Navigation
    # Validated query data. Hosts pass keyword arguments; keeping this value
    # internal keeps index choices out of the public API.
    class DestinationFilter
      attr_reader :tag, :sensitivity

      def initialize(tag: nil, sensitivity: nil)
        @tag = tag.nil? ? nil : normalized_tag(tag)
        @sensitivity = sensitivity.nil? ? nil : Destination.validated_sensitivity(sensitivity)

        freeze
      end

      def empty?
        tag.nil? && sensitivity.nil?
      end

      private

      def normalized_tag(tag)
        raise InvalidDestinationError.for(:tag, tag, "must be a Symbol or String") unless
          tag.is_a?(Symbol) || tag.is_a?(String)

        tag.to_sym
      end
    end

    # One process-wide owner of canonical Destination objects. Reads take the
    # current frozen snapshot; a write publishes a new snapshot in one
    # assignment, so a reader never sees a half-built index.
    class Registry
      EMPTY_LIST = [].freeze
      private_constant :EMPTY_LIST

      # One immutable point-in-time state. Every bucket keeps registration
      # order and points at the objects in `ordered`.
      class Snapshot
        attr_reader :ordered, :by_key, :by_tag, :by_sensitivity, :by_group, :search_document_by_key, :source_by_key

        def self.empty
          new(
            ordered: EMPTY_LIST,
            by_key: {},
            by_tag: {},
            by_sensitivity: {},
            by_group: {},
            search_document_by_key: {},
            source_by_key: {}
          )
        end

        def initialize(ordered:, by_key:, by_tag:, by_sensitivity:, by_group:, search_document_by_key:, source_by_key:)
          @ordered = ordered.freeze
          @by_key = by_key.freeze
          @by_tag = frozen_buckets(by_tag)
          @by_sensitivity = frozen_buckets(by_sensitivity)
          @by_group = frozen_buckets(by_group)
          @search_document_by_key = search_document_by_key.freeze
          @source_by_key = source_by_key.freeze

          freeze
        end

        def add(destination, source:)
          self.class.new(
            ordered: ordered + [destination],
            **bucket_indexes(destination),
            **lookup_indexes(destination, source)
          )
        end

        private

        def bucket_indexes(destination)
          {
            by_tag: appended(by_tag, destination.tags, destination),
            by_sensitivity: appended(by_sensitivity, [destination.sensitivity], destination),
            by_group: appended(by_group, destination.groups, destination)
          }
        end

        def lookup_indexes(destination, source)
          key = destination.key

          {
            by_key: by_key.merge(key => destination),
            search_document_by_key: search_document_by_key.merge(key => search_document(destination)),
            source_by_key: source_by_key.merge(key => source)
          }
        end

        def appended(buckets, names, destination)
          names.each_with_object(buckets.dup) do |name, copy|
            copy[name] = copy.fetch(name, EMPTY_LIST) + [destination]
          end
        end

        def search_document(destination)
          [destination.key, destination.label, destination.description, *destination.tags]
            .join(" ")
            .downcase
            .freeze
        end

        def frozen_buckets(buckets)
          buckets.transform_values(&:freeze).freeze
        end
      end
      private_constant :Snapshot

      def initialize
        @mutex = Mutex.new
        @snapshot = Snapshot.empty
      end

      def add(destination, source: nil)
        @mutex.synchronize do
          snapshot = @snapshot
          existing = snapshot.by_key[destination.key]
          return existing if existing == destination
          raise duplicate_error(snapshot, destination, source) if existing

          @snapshot = snapshot.add(destination, source: source)
          destination
        end
      end

      def destinations(filter)
        filtered(@snapshot, filter)
      end

      def group(name)
        @snapshot.by_group.fetch(name, EMPTY_LIST)
      end

      def search(query, filter)
        snapshot = @snapshot
        candidates = filtered(snapshot, filter)
        term = query.to_s.strip.downcase
        return candidates if term.empty?

        candidates.select { |destination| snapshot.search_document_by_key.fetch(destination.key, "").include?(term) }
                  .freeze
      end

      private

      def duplicate_error(snapshot, destination, source)
        DuplicateDestinationError.new(
          key: destination.key,
          existing: snapshot.by_key.fetch(destination.key),
          attempted: destination,
          existing_source: snapshot.source_by_key[destination.key],
          attempted_source: source
        )
      end

      def filtered(snapshot, filter)
        return snapshot.ordered if filter.empty?

        tagged = filter.tag && snapshot.by_tag.fetch(filter.tag, EMPTY_LIST)
        classified = filter.sensitivity && snapshot.by_sensitivity.fetch(filter.sensitivity, EMPTY_LIST)

        return classified if tagged.nil?
        return tagged if classified.nil?

        narrowed(tagged, classified, filter)
      end

      def narrowed(tagged, classified, filter)
        if tagged.size <= classified.size
          tagged.select { |destination| destination.sensitivity == filter.sensitivity }.freeze
        else
          classified.select { |destination| destination.tags.include?(filter.tag) }.freeze
        end
      end
    end

    private_constant :Registry, :DestinationFilter
  end
end
