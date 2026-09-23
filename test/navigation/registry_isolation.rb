# frozen_string_literal: true

# The registry is one process-wide object held in an ivar on the facade, so a
# test replaces it and restores it afterwards, the way engine_test.rb swaps
# @configuration. Clearing the registry is deliberately not public API.
module NavigationRegistryIsolation
  def setup
    @previous_registry = RecordingStudio::Navigation.instance_variable_get(:@registry)
    RecordingStudio::Navigation.instance_variable_set(:@registry, nil)
  end

  def teardown
    RecordingStudio::Navigation.instance_variable_set(:@registry, @previous_registry)
  end
end
