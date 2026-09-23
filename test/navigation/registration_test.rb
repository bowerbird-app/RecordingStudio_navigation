# frozen_string_literal: true

require "test_helper"
require "navigation/registry_isolation"

class NavigationRegistrationTest < Minitest::Test
  include NavigationRegistryIsolation

  def test_register_returns_the_canonical_frozen_destination
    destination = register_brands

    assert_equal "publications.brands", destination.key
    assert_equal "Brands", destination.label
    assert_equal "Manage publication brands", destination.description
    assert_equal "newspaper", destination.icon
    assert_equal %i[admin publications], destination.tags.to_a
    assert_equal %i[admin_search admin_sidebar], destination.groups.to_a
    assert_equal :normal, destination.sensitivity
    assert_predicate destination, :frozen?
  end

  def test_destinations_lists_registrations_in_order_and_is_frozen
    register_brands
    register_invoices

    destinations = RecordingStudio::Navigation.destinations

    assert_equal ["publications.brands", "billing.invoices"], destinations.map(&:key)
    assert_predicate destinations, :frozen?
  end

  def test_optional_attributes_default
    destination = RecordingStudio::Navigation.register(
      key: "billing.invoices",
      label: "Invoices",
      route: :invoices_path
    )

    assert_equal "", destination.description
    assert_nil destination.icon
    assert_empty destination.tags
    assert_empty destination.groups
    assert_equal :normal, destination.sensitivity
  end

  def test_key_label_and_route_are_required
    error = assert_raises(ArgumentError) do
      RecordingStudio::Navigation.register(label: "Invoices", route: :invoices_path)
    end
    assert_includes error.message, "key"

    assert_raises(ArgumentError) do
      RecordingStudio::Navigation.register(key: "billing.invoices", route: :invoices_path)
    end

    assert_raises(ArgumentError) do
      RecordingStudio::Navigation.register(key: "billing.invoices", label: "Invoices")
    end
  end

  def test_blank_key_and_label_are_invalid
    key_error = assert_raises(RecordingStudio::Navigation::InvalidDestinationError) do
      RecordingStudio::Navigation.register(key: "  ", label: "Invoices", route: :invoices_path)
    end

    label_error = assert_raises(RecordingStudio::Navigation::InvalidDestinationError) do
      RecordingStudio::Navigation.register(key: "billing.invoices", label: "", route: :invoices_path)
    end

    assert_equal :key, key_error.attribute
    assert_equal "  ", key_error.value
    assert_equal :label, label_error.attribute
    assert_equal "", label_error.value
    assert_empty RecordingStudio::Navigation.destinations
  end

  def test_keys_are_unique_per_registry
    register_brands
    register_invoices

    keys = RecordingStudio::Navigation.destinations.map(&:key)

    assert_equal keys.uniq, keys
    assert_equal 2, keys.size
  end

  def test_registering_the_same_definition_again_returns_the_existing_object
    first = register_brands
    second = RecordingStudio::Navigation.register(
      key: "publications.brands",
      label: "Brands",
      description: "Manage publication brands",
      route: :admin_publications_brands_path,
      icon: "newspaper",
      tags: %i[publications admin],
      groups: %i[admin_sidebar admin_search],
      sensitivity: :normal
    )

    assert_same first, second
    assert_equal ["publications.brands"], RecordingStudio::Navigation.destinations.map(&:key)
  end

  def test_duplicate_key_with_a_different_definition_raises_and_names_both_sites
    existing = RecordingStudio::Navigation.register(key: "billing.invoices", label: "Invoices", route: :invoices_path)
    existing_line = __LINE__ - 1

    error = assert_raises(RecordingStudio::Navigation::DuplicateDestinationError) do
      RecordingStudio::Navigation.register(key: "billing.invoices", label: "Invoice list", route: :invoices_path)
    end
    attempted_line = __LINE__ - 2

    assert_equal "billing.invoices", error.key
    assert_same existing, error.existing
    assert_equal "Invoice list", error.attempted.label
    assert_includes error.message, "#{__FILE__}:#{existing_line}"
    assert_includes error.message, "#{__FILE__}:#{attempted_line}"
    assert_equal [existing], RecordingStudio::Navigation.destinations
  end

  def test_destinations_are_immutable
    destination = register_brands

    assert_raises(FrozenError) { destination.instance_variable_set(:@label, "Renamed") }
    refute_respond_to destination, :label=
    refute_respond_to destination, :sensitivity=
    assert_predicate destination.tags, :frozen?
    assert_predicate destination.groups, :frozen?
    assert_predicate destination.route, :frozen?
  end

  def test_a_reloaded_registration_neither_duplicates_nor_clears
    registration = lambda do
      RecordingStudio::Navigation.register(
        key: "publications.brands",
        label: "Brands",
        description: "Manage publication brands",
        route: :admin_publications_brands_path,
        tags: [:admin]
      )
    end

    first = registration.call
    register_invoices
    second = registration.call

    assert_same first, second
    assert_equal ["publications.brands", "billing.invoices"], RecordingStudio::Navigation.destinations.map(&:key)
    refute_respond_to RecordingStudio::Navigation, :clear!
    refute_respond_to RecordingStudio::Navigation, :reset!
  end

  def test_two_independent_modules_register_into_one_registry
    publications = Module.new do
      def self.register_destinations
        RecordingStudio::Navigation.register(
          key: "publications.brands",
          label: "Brands",
          route: :admin_publications_brands_path,
          groups: [:admin_sidebar]
        )
      end
    end

    billing = Module.new do
      def self.register_destinations
        RecordingStudio::Navigation.register(
          key: "billing.invoices",
          label: "Invoices",
          route: :admin_billing_invoices_path,
          groups: [:admin_sidebar]
        )
      end
    end

    publications.register_destinations
    billing.register_destinations

    assert_equal(
      ["publications.brands", "billing.invoices"],
      RecordingStudio::Navigation.destinations.map(&:key)
    )
    assert_equal(
      ["publications.brands", "billing.invoices"],
      RecordingStudio::Navigation.group(:admin_sidebar).map(&:key)
    )
  end

  def test_sensitivity_defaults_to_normal_and_accepts_every_member
    assert_equal :normal, register_invoices.sensitivity

    sensitive = RecordingStudio::Navigation.register(
      key: "billing.payouts",
      label: "Payouts",
      route: :admin_billing_payouts_path,
      sensitivity: :sensitive
    )
    restricted = RecordingStudio::Navigation.register(
      key: "billing.ledger",
      label: "Ledger",
      route: :admin_billing_ledger_path,
      sensitivity: :restricted
    )

    assert_equal :sensitive, sensitive.sensitivity
    assert_equal :restricted, restricted.sensitivity
  end

  def test_unknown_sensitivity_is_rejected_at_registration
    error = assert_raises(RecordingStudio::Navigation::InvalidDestinationError) do
      RecordingStudio::Navigation.register(
        key: "billing.invoices",
        label: "Invoices",
        route: :admin_billing_invoices_path,
        sensitivity: :secret
      )
    end

    assert_equal :sensitivity, error.attribute
    assert_equal :secret, error.value
    assert_empty RecordingStudio::Navigation.destinations
  end

  def test_sensitivity_is_advisory_and_exposes_no_authorization
    destination = RecordingStudio::Navigation.register(
      key: "billing.ledger",
      label: "Ledger",
      route: :admin_billing_ledger_path,
      sensitivity: :restricted
    )

    assert_equal :restricted, destination.sensitivity
    %i[authorized? access role permission permitted? visible_to? can_access?].each do |method_name|
      refute_respond_to destination, method_name
    end
  end

  def test_tags_and_groups_are_symbol_sets_that_ignore_order_and_duplicates
    destination = RecordingStudio::Navigation.register(
      key: "publications.brands",
      label: "Brands",
      route: :admin_publications_brands_path,
      tags: ["admin", :admin, :publications],
      groups: [:admin_sidebar, "admin_sidebar"]
    )

    assert_equal Set[:admin, :publications], destination.tags
    assert_equal Set[:admin_sidebar], destination.groups
    assert_equal Set[:publications, :admin], destination.tags
  end

  def test_blank_tag_entries_are_invalid
    error = assert_raises(RecordingStudio::Navigation::InvalidDestinationError) do
      RecordingStudio::Navigation.register(
        key: "publications.brands",
        label: "Brands",
        route: :admin_publications_brands_path,
        tags: [""]
      )
    end

    assert_equal :tags, error.attribute
  end

  def test_the_registry_and_its_internals_are_not_public_constants
    public_constants = RecordingStudio::Navigation.constants.sort

    assert_equal(
      %i[ConfigurationError Destination DuplicateDestinationError InvalidDestinationError Route RouteResolutionError],
      public_constants
    )

    error = assert_raises(NameError) { RecordingStudio::Navigation::Registry }

    assert_includes error.message, "private constant RecordingStudio::Navigation::Registry"
  end

  private

  def register_brands
    RecordingStudio::Navigation.register(
      key: "publications.brands",
      label: "Brands",
      description: "Manage publication brands",
      route: :admin_publications_brands_path,
      icon: "newspaper",
      tags: %i[admin publications],
      groups: %i[admin_search admin_sidebar],
      sensitivity: :normal
    )
  end

  def register_invoices
    RecordingStudio::Navigation.register(
      key: "billing.invoices",
      label: "Invoices",
      route: :admin_billing_invoices_path
    )
  end
end
