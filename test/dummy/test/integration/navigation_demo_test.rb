# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class NavigationDemoTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  EXAMPLE_KEYS = [
    "dummy.home",
    "dummy.docs.install",
    "dummy.docs.config",
    "dummy.docs.recordable_types",
    "dummy.root_switch",
    "dummy.docs.recordings_tree",
    "dummy.docs.methods"
  ].freeze

  setup do
    user = User.find_or_create_by!(email: "navigation-demo@example.com") do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end

    sign_in user

    RecordingStudio.root_recording_for(Workspace.find_or_create_by!(name: "Navigation Workspace"))
  end

  test "the dummy initializer registers the example destinations in order" do
    assert_equal EXAMPLE_KEYS, RecordingStudio::Navigation.destinations.map(&:key)
  end

  test "a host route resolves through main_app" do
    assert_equal "/docs/install", resolve("dummy.docs.install")
    assert_equal "/", resolve("dummy.home")
  end

  test "a mounted route resolves to a path that includes the host mount prefix" do
    path = resolve("dummy.root_switch")

    assert_equal "/recording_studio_root_switchable/v1/root_switch", path
    assert path.start_with?("/recording_studio_root_switchable"), "expected the host mount prefix in #{path}"
  end

  test "a callable route resolves through the context it is given" do
    assert_equal "/docs/methods#example-method", resolve("dummy.docs.methods")
  end

  test "a helper that is not drawn raises a route resolution error instead of a path" do
    route = RecordingStudio::Navigation::Route.host(:not_drawn_path)

    error = assert_raises(RecordingStudio::Navigation::RouteResolutionError) { route.resolve(resolution_context) }

    assert_equal "Host route helper :not_drawn_path is not drawn in this application.", error.message
  end

  test "an engine that is not mounted raises a route resolution error" do
    route = RecordingStudio::Navigation::Route.mounted(engine: "Publications::Engine", helper: :brands_path)

    error = assert_raises(RecordingStudio::Navigation::RouteResolutionError) { route.resolve(resolution_context) }

    assert_includes error.message, "Publications::Engine is not mounted in this application"
  end

  test "the demo page lists every destination with a request-time path" do
    get root_path

    assert_response :success
    assert_select "h1", text: "Navigation Demo"
    assert_select "a[href=?]", "/?filter=admin"
    assert_select "a[href=?]", "/?filter=sensitive"
    assert_select "a[href=?]", "/?filter=all"
    EXAMPLE_KEYS.each { |key| assert_includes response.body, key }
    assert_includes response.body, "/recording_studio_root_switchable/v1/root_switch"
    assert_includes response.body, "/docs/install"
    assert_includes response.body, "/docs/methods#example-method"
    assert_includes response.body, "7 destinations"
    refute_includes response.body, "is not drawn in this application"
  end

  test "the admin filter keeps only destinations tagged admin" do
    get root_path(filter: "admin")

    assert_response :success
    assert_includes response.body, "dummy.docs.config"
    assert_includes response.body, "dummy.root_switch"
    assert_includes response.body, "4 destinations"
    refute_includes response.body, "dummy.docs.install"
    refute_includes response.body, "dummy.home"
  end

  test "the sensitive filter keeps only sensitive destinations" do
    get root_path(filter: "sensitive")

    assert_response :success
    assert_includes response.body, "dummy.root_switch"
    assert_includes response.body, "1 destination"
    refute_includes response.body, "dummy.docs.config"
    refute_includes response.body, "dummy.home"
  end

  test "an unknown filter falls back to every destination" do
    get root_path(filter: "nope")

    assert_response :success
    assert_includes response.body, "7 destinations"
  end

  private

  def resolve(key)
    destination = RecordingStudio::Navigation.destinations.find { |candidate| candidate.key == key }

    destination.route.resolve(resolution_context)
  end

  # Resolution needs a request-time context: main_app and the host's mount
  # proxies both come from the running application's route set.
  def resolution_context
    controller = ApplicationController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.view_context
  end
end
