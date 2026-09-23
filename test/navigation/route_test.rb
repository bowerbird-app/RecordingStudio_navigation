# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "navigation/registry_isolation"

class NavigationRouteTest < Minitest::Test
  include NavigationRegistryIsolation

  # A named engine class so the mount scan has a real class name to compare.
  class PublicationsEngine < ::Rails::Engine; end

  # Mirrors the two layers a mounted engine sits behind in a Rails route set:
  # the journey route's constraints wrapper, then the engine endpoint.
  Endpoint = Struct.new(:app)
  FakeRoute = Struct.new(:name, :app)

  class FakeProxy
    def initialize(paths)
      @paths = paths
    end

    def respond_to_missing?(name, include_private = false)
      @paths.key?(name) || super
    end

    def method_missing(name, **params)
      return super unless @paths.key?(name)

      path = @paths.fetch(name)
      return path if params.empty?

      "#{path}?#{params.map { |key, value| "#{key}=#{value}" }.join('&')}"
    end
  end

  class FakeContext
    attr_reader :main_app, :publications

    def initialize(host_paths: {}, mounted_paths: {})
      @main_app = FakeProxy.new(host_paths)
      @publications = FakeProxy.new(mounted_paths)
    end
  end

  def test_a_symbol_route_is_stored_as_a_host_helper
    route = register(route: :admin_publications_brands_path).route

    assert_equal :host, route.kind
    assert_equal :admin_publications_brands_path, route.helper
    assert_nil route.engine_name
    assert_empty route.params
    assert_predicate route, :frozen?
  end

  def test_a_string_route_is_stored_as_a_host_helper_symbol
    route = register(route: "admin_publications_brands_path").route

    assert_equal :host, route.kind
    assert_equal :admin_publications_brands_path, route.helper
  end

  def test_a_hash_route_is_stored_as_a_mounted_engine_name_string
    route = register(route: { engine: PublicationsEngine, helper: :brands_path, params: { page: 2 } }).route

    assert_equal :mounted, route.kind
    assert_equal "NavigationRouteTest::PublicationsEngine", route.engine_name
    assert_equal :brands_path, route.helper
    assert_equal({ page: 2 }, route.params)
    assert_predicate route.params, :frozen?
  end

  def test_a_mounted_engine_may_be_named_by_string
    route = register(route: { engine: "Publications::Engine", helper: :brands_path }).route

    assert_equal "Publications::Engine", route.engine_name
    assert_predicate route.engine_name, :frozen?
  end

  def test_a_proc_route_is_stored_as_a_callable
    callable = ->(context) { context.main_app.admin_publications_brands_path }
    route = register(route: callable).route

    assert_equal :callable, route.kind
    assert_same callable, route.callable
    assert_nil route.helper
  end

  def test_an_unsupported_route_value_is_invalid
    error = assert_raises(RecordingStudio::Navigation::InvalidDestinationError) do
      register(route: 42)
    end

    assert_equal :route, error.attribute
    assert_equal 42, error.value
  end

  def test_a_mounted_route_requires_an_engine_and_a_helper
    error = assert_raises(RecordingStudio::Navigation::InvalidDestinationError) do
      register(route: { engine: PublicationsEngine })
    end

    assert_equal :route, error.attribute
    assert_includes error.message, "mounted route requires helper"
  end

  def test_host_routes_resolve_through_main_app
    route = register(route: :admin_publications_brands_path).route
    context = FakeContext.new(host_paths: { admin_publications_brands_path: "/admin/publications/brands" })

    assert_equal "/admin/publications/brands", route.resolve(context)
  end

  def test_host_routes_pass_params_to_the_helper
    route = register(route: RecordingStudio::Navigation::Route.host(:brand_path, params: { id: 7 })).route
    context = FakeContext.new(host_paths: { brand_path: "/admin/brands" })

    assert_equal "/admin/brands?id=7", route.resolve(context)
  end

  def test_a_host_helper_that_is_not_drawn_raises_a_route_resolution_error
    route = register(route: :missing_path).route
    context = FakeContext.new

    error = assert_raises(RecordingStudio::Navigation::RouteResolutionError) { route.resolve(context) }

    assert_equal "Host route helper :missing_path is not drawn in this application.", error.message
  end

  def test_a_context_without_main_app_raises_a_route_resolution_error
    route = register(route: :admin_publications_brands_path).route

    error = assert_raises(RecordingStudio::Navigation::RouteResolutionError) { route.resolve(Object.new) }

    assert_equal(
      "Object does not respond to main_app, so :admin_publications_brands_path cannot be resolved.",
      error.message
    )
  end

  def test_mounted_routes_resolve_through_the_mount_proxy_named_by_the_host
    route = register(route: { engine: PublicationsEngine, helper: :brands_path }).route
    context = FakeContext.new(mounted_paths: { brands_path: "/publications/brands" })

    with_mounted_routes([FakeRoute.new("publications", Endpoint.new(PublicationsEngine))]) do
      assert_equal "/publications/brands", route.resolve(context)
    end
  end

  def test_an_unmounted_engine_raises_a_route_resolution_error
    route = register(route: { engine: PublicationsEngine, helper: :brands_path }).route
    context = FakeContext.new(mounted_paths: { brands_path: "/publications/brands" })

    error = assert_raises(RecordingStudio::Navigation::RouteResolutionError) do
      with_mounted_routes([]) { route.resolve(context) }
    end

    assert_includes error.message, "NavigationRouteTest::PublicationsEngine is not mounted in this application"
  end

  def test_an_engine_mounted_twice_raises_a_route_resolution_error
    route = register(route: { engine: PublicationsEngine, helper: :brands_path }).route
    context = FakeContext.new(mounted_paths: { brands_path: "/publications/brands" })
    mounts = [
      FakeRoute.new("publications", Endpoint.new(PublicationsEngine)),
      FakeRoute.new("archive_publications", Endpoint.new(PublicationsEngine))
    ]

    error = assert_raises(RecordingStudio::Navigation::RouteResolutionError) do
      with_mounted_routes(mounts) { route.resolve(context) }
    end

    assert_includes error.message, "is mounted more than once (publications, archive_publications)"
  end

  def test_a_mounted_helper_that_is_not_drawn_raises_a_route_resolution_error
    route = register(route: { engine: PublicationsEngine, helper: :missing_path }).route
    context = FakeContext.new

    error = assert_raises(RecordingStudio::Navigation::RouteResolutionError) do
      with_mounted_routes([FakeRoute.new("publications", Endpoint.new(PublicationsEngine))]) do
        route.resolve(context)
      end
    end

    assert_equal(
      "Mounted route helper :missing_path is not drawn in NavigationRouteTest::PublicationsEngine.",
      error.message
    )
  end

  def test_callable_routes_receive_the_resolution_context
    route = register(route: ->(context) { context.main_app.admin_publications_brands_path }).route
    context = FakeContext.new(host_paths: { admin_publications_brands_path: "/admin/publications/brands" })

    assert_equal "/admin/publications/brands", route.resolve(context)
  end

  def test_two_callables_with_the_same_body_are_different_definitions
    body = "->(context) { context.main_app.admin_publications_brands_path }"
    register(route: eval(body)) # rubocop:disable Security/Eval

    assert_raises(RecordingStudio::Navigation::DuplicateDestinationError) do
      register(route: eval(body)) # rubocop:disable Security/Eval
    end
  end

  def test_the_same_callable_object_is_the_same_definition
    callable = ->(context) { context.main_app.admin_publications_brands_path }

    assert_same register(route: callable), register(route: callable)
  end

  def test_an_equivalent_host_route_object_is_the_same_definition
    first = register(route: :admin_publications_brands_path)
    second = register(route: RecordingStudio::Navigation::Route.host(:admin_publications_brands_path))

    assert_same first, second
  end

  def test_a_route_instance_is_kept_as_given
    route = RecordingStudio::Navigation::Route.mounted(engine: PublicationsEngine, helper: :brands_path)

    assert_same route, register(route: route).route
  end

  def test_route_params_are_copied_and_deeply_frozen
    params = { filter: { state: +"open" } }
    route = RecordingStudio::Navigation::Route.host(:brands_path, params: params)

    params[:filter][:state] << "!"

    assert_equal({ filter: { state: "open" } }, route.params)
    assert_predicate route.params[:filter], :frozen?
    assert_predicate route.params[:filter][:state], :frozen?
  end

  def test_resolution_never_calls_engine_route_url_helpers
    source = File.read(File.expand_path("../../lib/recording_studio/navigation/route.rb", __dir__))

    refute_includes source, "url_helpers"
  end

  private

  def register(route:, key: "publications.brands")
    RecordingStudio::Navigation.register(key: key, label: "Brands", route: route)
  end

  def with_mounted_routes(routes, &block)
    route_set = Struct.new(:routes).new(routes)
    application = Struct.new(:routes).new(route_set)

    ::Rails.stub(:application, application, &block)
  end
end
