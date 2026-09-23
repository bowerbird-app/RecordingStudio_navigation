# frozen_string_literal: true

require "test_helper"
require "navigation/registry_isolation"

class NavigationQueryTest < Minitest::Test
  include NavigationRegistryIsolation

  def setup
    super
    register_example_destinations
  end

  def test_destinations_returns_every_registration_in_order
    assert_equal(
      ["publications.brands", "publications.issues", "billing.invoices", "billing.ledger"],
      RecordingStudio::Navigation.destinations.map(&:key)
    )
  end

  def test_tag_filter_returns_only_tagged_destinations
    assert_equal(
      ["publications.brands", "billing.invoices", "billing.ledger"],
      RecordingStudio::Navigation.destinations(tag: :admin).map(&:key)
    )
    assert_equal(
      ["publications.brands", "publications.issues"],
      RecordingStudio::Navigation.destinations(tag: :publications).map(&:key)
    )
  end

  def test_tag_filter_accepts_a_string
    assert_equal(
      ["publications.brands", "publications.issues"],
      RecordingStudio::Navigation.destinations(tag: "publications").map(&:key)
    )
  end

  def test_sensitivity_filter_returns_only_that_sensitivity
    assert_equal(
      ["publications.brands", "publications.issues"],
      RecordingStudio::Navigation.destinations(sensitivity: :normal).map(&:key)
    )
    assert_equal ["billing.invoices"], RecordingStudio::Navigation.destinations(sensitivity: :sensitive).map(&:key)
    assert_equal ["billing.ledger"], RecordingStudio::Navigation.destinations(sensitivity: :restricted).map(&:key)
  end

  def test_tag_and_sensitivity_filters_combine
    assert_equal(
      ["publications.brands"],
      RecordingStudio::Navigation.destinations(tag: :admin, sensitivity: :normal).map(&:key)
    )
    assert_equal(
      ["billing.invoices"],
      RecordingStudio::Navigation.destinations(tag: :billing, sensitivity: :sensitive).map(&:key)
    )
    assert_empty RecordingStudio::Navigation.destinations(tag: :publications, sensitivity: :restricted)
  end

  def test_unknown_tag_returns_an_empty_frozen_list
    destinations = RecordingStudio::Navigation.destinations(tag: :nonexistent)

    assert_empty destinations
    assert_predicate destinations, :frozen?
  end

  def test_unknown_sensitivity_is_rejected_at_query_time
    error = assert_raises(RecordingStudio::Navigation::InvalidDestinationError) do
      RecordingStudio::Navigation.destinations(sensitivity: :secret)
    end

    assert_equal :sensitivity, error.attribute
    assert_equal :secret, error.value
  end

  def test_group_returns_group_members_in_registration_order
    assert_equal(
      ["publications.brands", "billing.invoices", "billing.ledger"],
      RecordingStudio::Navigation.group(:admin_sidebar).map(&:key)
    )
    assert_equal(
      ["publications.brands", "publications.issues"],
      RecordingStudio::Navigation.group(:publications_sidebar).map(&:key)
    )
  end

  def test_group_accepts_a_string_and_returns_a_frozen_list
    destinations = RecordingStudio::Navigation.group("admin_sidebar")

    assert_equal ["publications.brands", "billing.invoices", "billing.ledger"], destinations.map(&:key)
    assert_predicate destinations, :frozen?
  end

  def test_unknown_group_is_empty
    assert_empty RecordingStudio::Navigation.group(:nonexistent)
  end

  def test_groups_are_independent_of_tags
    destination = RecordingStudio::Navigation.destinations.first

    assert_equal Set[:admin, :publications], destination.tags
    assert_equal Set[:admin_sidebar, :publications_sidebar], destination.groups
    assert_empty RecordingStudio::Navigation.group(:admin)
    assert_empty RecordingStudio::Navigation.destinations(tag: :admin_sidebar)
  end

  def test_search_matches_label_description_key_and_tags
    assert_equal ["publications.brands"], RecordingStudio::Navigation.search("Brands").map(&:key)
    assert_equal ["publications.issues"], RecordingStudio::Navigation.search("back issues").map(&:key)
    assert_equal ["billing.ledger"], RecordingStudio::Navigation.search("billing.ledger").map(&:key)
    assert_equal(
      ["publications.brands", "publications.issues"],
      RecordingStudio::Navigation.search("publications").map(&:key)
    )
  end

  def test_search_is_case_insensitive_and_matches_substrings
    assert_equal ["publications.brands"], RecordingStudio::Navigation.search("bRaN").map(&:key)
  end

  def test_search_returns_nothing_for_an_unmatched_query
    assert_empty RecordingStudio::Navigation.search("nothing matches this")
  end

  def test_blank_search_returns_the_filtered_list
    assert_equal RecordingStudio::Navigation.destinations, RecordingStudio::Navigation.search("")
    assert_equal RecordingStudio::Navigation.destinations, RecordingStudio::Navigation.search("   ")
    assert_equal(
      ["billing.invoices"],
      RecordingStudio::Navigation.search("", sensitivity: :sensitive).map(&:key)
    )
  end

  def test_search_honours_tag_and_sensitivity_filters
    assert_equal(
      ["billing.ledger"],
      RecordingStudio::Navigation.search("ledger", tag: :admin, sensitivity: :restricted).map(&:key)
    )
    assert_empty RecordingStudio::Navigation.search("brands", tag: :billing)
  end

  private

  def register_example_destinations
    RecordingStudio::Navigation.register(
      key: "publications.brands",
      label: "Brands",
      description: "Manage publication brands",
      route: :admin_publications_brands_path,
      tags: %i[admin publications],
      groups: %i[admin_sidebar publications_sidebar]
    )
    RecordingStudio::Navigation.register(
      key: "publications.issues",
      label: "Issues",
      description: "Browse back issues",
      route: :admin_publications_issues_path,
      tags: [:publications],
      groups: [:publications_sidebar]
    )
    RecordingStudio::Navigation.register(
      key: "billing.invoices",
      label: "Invoices",
      description: "Customer invoices",
      route: :admin_billing_invoices_path,
      tags: %i[admin billing],
      groups: [:admin_sidebar],
      sensitivity: :sensitive
    )
    RecordingStudio::Navigation.register(
      key: "billing.ledger",
      label: "Ledger",
      description: "General ledger",
      route: :admin_billing_ledger_path,
      tags: %i[admin billing],
      groups: [:admin_sidebar],
      sensitivity: :restricted
    )
  end
end
