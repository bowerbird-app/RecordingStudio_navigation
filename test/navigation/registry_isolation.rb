# frozen_string_literal: true

module NavigationRegistryIsolation
  def setup
    @previous_registry = RecordingStudio::Navigation.instance_variable_get(:@registry)
    RecordingStudio::Navigation.instance_variable_set(:@registry, nil)
  end

  def teardown
    RecordingStudio::Navigation.instance_variable_set(:@registry, @previous_registry)
  end
end
