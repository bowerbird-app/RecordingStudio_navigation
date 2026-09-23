# frozen_string_literal: true

module RecordingStudio
  module Navigation
    # Where a destination points. A Route stores identity only: a helper name,
    # an engine name, or a callable. Paths are built at request time, never at
    # boot, because a mounted engine's path depends on the host's mount point.
    class Route
      KINDS = %i[host mounted callable].freeze
      EMPTY_PARAMS = {}.freeze

      # Finds the proxy name the host gave one mounted engine. The scan runs per
      # resolve because mounts can change with the route set, and because `as:`
      # lets a host name a mount something other than the engine name.
      class MountScan
        UNWRAP_LIMIT = 10
        private_constant :UNWRAP_LIMIT

        def initialize(engine_name)
          @engine_name = engine_name
        end

        def proxy_names
          routes.filter_map do |route|
            next unless mounted_engine_name(route) == @engine_name

            route.name&.to_sym
          end.uniq
        end

        private

        def routes
          application = defined?(::Rails) ? ::Rails.application : nil
          return application.routes.routes if application

          raise RouteResolutionError, "A Rails application is required to resolve a route in #{@engine_name}."
        end

        def mounted_engine_name(route)
          endpoint = route.app

          UNWRAP_LIMIT.times do
            return endpoint_class(endpoint).name if engine_endpoint?(endpoint)
            break unless endpoint.respond_to?(:app)

            inner = endpoint.app
            break if inner.nil? || inner.equal?(endpoint)

            endpoint = inner
          end

          nil
        end

        def engine_endpoint?(endpoint)
          return false unless defined?(::Rails::Engine)

          klass = endpoint_class(endpoint)

          klass ? !!(klass <= ::Rails::Engine) : false
        end

        def endpoint_class(endpoint)
          klass = endpoint.is_a?(Module) ? endpoint : endpoint.class

          klass if klass.is_a?(Class)
        end
      end
      private_constant :MountScan

      attr_reader :kind, :helper, :engine_name, :params, :callable

      class << self
        def coerce(value)
          case value
          when Route then value
          when Symbol, String then host(value)
          when Hash then mounted(**mounted_options(value))
          when Proc then callable(value)
          else
            raise InvalidDestinationError.for(:route, value, "must be a helper name, Hash, callable, or Route")
          end
        end

        def host(helper, params: EMPTY_PARAMS)
          new(kind: :host, helper: helper, params: params)
        end

        def mounted(engine:, helper:, params: EMPTY_PARAMS)
          new(kind: :mounted, engine_name: engine, helper: helper, params: params)
        end

        def callable(callable)
          new(kind: :callable, callable: callable)
        end

        private

        def mounted_options(value)
          options = value.transform_keys(&:to_sym)
          unknown = options.keys - %i[engine helper params]
          missing = %i[engine helper] - options.keys
          raise InvalidDestinationError.for(:route, value, "accepts engine, helper, and params") unless unknown.empty?
          raise InvalidDestinationError.for(:route, value, "mounted route requires #{missing.join(' and ')}") unless missing.empty?

          options
        end
      end

      def initialize(kind:, helper: nil, engine_name: nil, params: EMPTY_PARAMS, callable: nil)
        @kind = validated_kind(kind)
        @params = frozen_params(params)

        if @kind == :callable
          @callable = validated_callable(callable)
        else
          @helper = validated_helper(helper)
          @engine_name = validated_engine_name(engine_name) if @kind == :mounted
        end

        freeze
      end

      # The only operation that builds a path.
      def resolve(context)
        case kind
        when :host then resolve_host(context)
        when :mounted then resolve_mounted(context)
        else callable.call(context)
        end
      end

      def ==(other)
        return false unless other.is_a?(Route)
        return false unless kind == other.kind
        return callable.equal?(other.callable) if kind == :callable

        helper == other.helper && engine_name == other.engine_name && params == other.params
      end
      alias eql? ==

      def hash
        return [self.class, kind, callable.object_id].hash if kind == :callable

        [self.class, kind, helper, engine_name, params].hash
      end

      private

      # Host helpers go through main_app so a mounted engine's own route set
      # cannot shadow them.
      def resolve_host(context)
        unless context.respond_to?(:main_app)
          raise RouteResolutionError,
                "#{context.class} does not respond to main_app, so #{helper.inspect} cannot be resolved."
        end

        path_from(context.main_app, drawn_in: "this application")
      end

      def resolve_mounted(context)
        proxy_name = mount_proxy_name
        unless context.respond_to?(proxy_name)
          raise RouteResolutionError,
                "#{context.class} does not respond to #{proxy_name}, so #{helper.inspect} cannot be resolved."
        end

        path_from(context.public_send(proxy_name), drawn_in: engine_name)
      end

      def path_from(proxy, drawn_in:)
        label = kind == :mounted ? "Mounted route helper" : "Host route helper"
        raise RouteResolutionError, "#{label} #{helper.inspect} is not drawn in #{drawn_in}." unless
          proxy.respond_to?(helper)

        proxy.public_send(helper, **params)
      end

      def mount_proxy_name
        names = MountScan.new(engine_name).proxy_names
        return names.first if names.size == 1

        raise RouteResolutionError, mount_ambiguity_message(names)
      end

      def mount_ambiguity_message(names)
        if names.empty?
          "#{engine_name} is not mounted in this application, so #{helper.inspect} cannot be resolved. " \
            "Register a callable route when the path is not a single mount."
        else
          "#{engine_name} is mounted more than once (#{names.join(', ')}), so #{helper.inspect} is ambiguous. " \
            "Register a callable route to choose a mount."
        end
      end

      def validated_kind(kind)
        return kind.to_sym if KINDS.include?(kind.to_s.to_sym)

        raise InvalidDestinationError.for(:kind, kind, "must be one of #{KINDS.map(&:inspect).join(', ')}")
      end

      def validated_helper(helper)
        raise InvalidDestinationError.for(:helper, helper, "must be a Symbol or String") unless
          helper.is_a?(Symbol) || helper.is_a?(String)
        raise InvalidDestinationError.for(:helper, helper, "cannot be blank") if helper.to_s.strip.empty?

        helper.to_sym
      end

      def validated_engine_name(engine)
        name = engine.is_a?(Module) ? engine.name : engine.to_s
        raise InvalidDestinationError.for(:engine, engine, "must be a named class, module, or String") if
          name.nil? || name.strip.empty?

        name.dup.freeze
      end

      def validated_callable(callable)
        return callable if callable.respond_to?(:call)

        raise InvalidDestinationError.for(:route, callable, "must respond to call")
      end

      def frozen_params(params)
        raise InvalidDestinationError.for(:params, params, "must be a Hash") unless params.is_a?(Hash)

        params.transform_values { |value| deep_frozen(value) }.freeze
      end

      def deep_frozen(value)
        case value
        when Hash then value.transform_values { |entry| deep_frozen(entry) }.freeze
        when Array then value.map { |entry| deep_frozen(entry) }.freeze
        when String then value.dup.freeze
        else value
        end
      end
    end
  end
end
