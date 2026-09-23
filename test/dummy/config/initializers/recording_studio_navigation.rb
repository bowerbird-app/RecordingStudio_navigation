# frozen_string_literal: true

RecordingStudio::Navigation.register(
  key: "dummy.home",
  label: "Dummy home",
  description: "The navigation demo page itself",
  route: :root_path,
  icon: "home",
  tags: [:demo],
  groups: [:demo_primary]
)

RecordingStudio::Navigation.register(
  key: "dummy.docs.install",
  label: "Install guide",
  description: "How a host app installs this addon",
  route: :docs_install_path,
  icon: "wrench",
  tags: [:docs],
  groups: [:demo_docs]
)

RecordingStudio::Navigation.register(
  key: "dummy.docs.config",
  label: "Configuration",
  description: "Configuration settings the addon exposes",
  route: :docs_config_path,
  icon: "cog",
  tags: %i[docs admin],
  groups: [:demo_docs]
)

RecordingStudio::Navigation.register(
  key: "dummy.docs.recordable_types",
  label: "Recordable types",
  description: "Recordable declarations in the dummy host app",
  route: :docs_recordable_types_path,
  icon: "queue_list",
  tags: %i[docs admin],
  groups: [:demo_docs]
)

RecordingStudio::Navigation.register(
  key: "dummy.root_switch",
  label: "Root switch",
  description: "Mounted Root Switchable engine endpoint",
  route: { engine: RecordingStudioRootSwitchable::Engine, helper: :root_switch_path },
  icon: "arrows_right_left",
  tags: [:admin],
  groups: [:demo_primary],
  sensitivity: :sensitive
)

RecordingStudio::Navigation.register(
  key: "dummy.docs.recordings_tree",
  label: "Recordings tree",
  description: "Every recording in the dummy host app",
  route: :docs_recordings_tree_path,
  icon: "list_bullet",
  tags: %i[docs admin],
  groups: [:demo_docs],
  sensitivity: :restricted
)

RecordingStudio::Navigation.register(
  key: "dummy.docs.methods",
  label: "Methods",
  description: "Callable route that adds an anchor to a host path",
  route: ->(context) { context.main_app.docs_methods_path(anchor: "example-method") },
  icon: "code_bracket",
  tags: [:docs],
  groups: [:demo_docs]
)
