# RecordingStudioNavigation

A shared registry of navigable destinations for Recording Studio addons.

Gems declare where they can be reached. The host app decides what to show, in what order, and to whom. The public API is `RecordingStudio::Navigation`.

The registry stores destination metadata in memory. Hosts render sidebars, search, and command palettes from that metadata. Recording Studio Accessible and the host own access control.

## What a destination is

A destination is an immutable record with a globally unique key, a label, a route, and optional metadata:

| Attribute     | Required | Notes                                                                  |
|---------------|----------|------------------------------------------------------------------------|
| `key`         | yes      | Globally unique. A different definition for the same key raises `DuplicateDestinationError` |
| `label`       | yes      | Human-facing text the host may show as-is                              |
| `route`       | yes      | Host helper, mounted engine helper, or callable. Resolved per request   |
| `description` | no       | Defaults to `""`. Searchable                                           |
| `icon`        | no       | Defaults to `nil`. A name string; this gem never renders it            |
| `tags`        | no       | Defaults to `[]`. Stored as a Set of Symbols, so order does not matter  |
| `groups`      | no       | Defaults to `[]`. Named buckets a host can query directly               |
| `sensitivity` | no       | `:normal` (default), `:sensitive`, or `:restricted`. Advisory only      |

## How to register a destination

Register from your gem's `lib/` (an engine initializer or a required file), not from reloadable `app/` code:

```ruby
RecordingStudio::Navigation.register(
  key: "publications.brands",
  label: "Brands",
  description: "Manage publication brands",
  route: :admin_publications_brands_path,
  icon: "newspaper",
  tags: [:admin, :publications],
  groups: [:admin_search, :admin_sidebar],
  sensitivity: :normal
)
```

Only `key`, `label`, and `route` are required:

```ruby
RecordingStudio::Navigation.register(key: "billing.invoices", label: "Invoices", route: :invoices_path)
```

`register` returns the canonical `RecordingStudio::Navigation::Destination`. Registering the identical definition again returns the object that is already registered, so a re-required file or a re-run initializer cannot duplicate a destination. Registering the same key with a *different* definition raises `RecordingStudio::Navigation::DuplicateDestinationError`, which names both declaration sites and leaves the registry untouched.

### Route kinds

Routes store identity, never a path string. Nothing is resolved at boot, because a mounted engine's path depends on where the host mounted it.

```ruby
# Host helper. Resolved through main_app.
route: :admin_publications_brands_path

# Mounted engine helper. The engine is stored by name and the mount is found
# in the host's route set at request time.
route: { engine: Publications::Engine, helper: :brands_path, params: { page: 1 } }

# Callable. Use it when a path needs more than one helper call, or when the
# same engine is mounted more than once.
route: ->(context) { context.main_app.docs_methods_path(anchor: "example-method") }
```

Build the path inside a request, from a view or controller context:

```ruby
destination.route.resolve(self)
```

Resolution raises `RecordingStudio::Navigation::RouteResolutionError` when a helper is not drawn, when the engine is not mounted, or when the engine is mounted more than once. A host that renders destinations from several gems should rescue it:

```ruby
def destination_path(destination)
  destination.route.resolve(self)
rescue RecordingStudio::Navigation::RouteResolutionError
  nil
end
```

## How to query destinations

Every query returns a frozen Array in registration order.

```ruby
# Everything.
RecordingStudio::Navigation.destinations

# One tag, one sensitivity, or both.
RecordingStudio::Navigation.destinations(tag: :admin)
RecordingStudio::Navigation.destinations(sensitivity: :sensitive)
RecordingStudio::Navigation.destinations(tag: :admin, sensitivity: :normal)

# One named group.
RecordingStudio::Navigation.group(:admin_sidebar)

# Case-insensitive substring over key, label, description, and tag names.
RecordingStudio::Navigation.search("brand")
RecordingStudio::Navigation.search("brand", tag: :admin)
```

An unknown tag or group returns an empty list. An unknown sensitivity raises `RecordingStudio::Navigation::InvalidDestinationError` at registration and at query time. A blank search query returns the filtered list unchanged.

### Tags versus groups

Both are Sets of Symbols and both are free-form; they answer different questions.

- A **tag** classifies a destination: "this is an admin thing", "this belongs to publications". Filter with `destinations(tag:)`.
- A **group** is a placement bucket a gem opts into: "offer me in the admin sidebar", "include me in admin search". Read with `group(name)`.

A destination can carry several of each, and a group is never implied by a tag.

## Sensitivity is advisory, not authorization

`sensitivity` is a hint about how careful a host should be with a destination. It answers "how sensitive is this?", never "may this person see it?".

There is no `authorized?`, `access`, `role`, or `permission` in this gem. Recording Studio Accessible and the host app own access control. A destination describes a place. It does not decide who may open it.

## How a host filters before display

The host asks the registry for candidates, drops what the current actor may not reach, and only then renders:

```ruby
# app/helpers/navigation_helper.rb
def admin_sidebar_destinations
  RecordingStudio::Navigation.group(:admin_sidebar).select do |destination|
    next false if destination.sensitivity == :restricted && !current_user.admin?

    policy_allows?(current_user, destination.key)
  end
end
```

```erb
<% admin_sidebar_destinations.each do |destination| %>
  <% path = destination_path(destination) %>
  <%= link_to destination.label, path if path %>
<% end %>
```

Three rules keep this boundary clean:

1. The registry never hides a destination on its own. Filtering is the host's job.
2. Destinations are frozen. Presentation overrides belong to the host's view code, not to the canonical record.
3. Resolution happens during the request, so paths always match the host's current mounts.

## Reload safety

The registry lives on `RecordingStudio::Navigation` in `lib/`, is allocated once per process, and is never cleared by the Rails reloader. There is no `clear!` and no `to_prepare` rebuild, so a code reload can neither duplicate nor erase what gems declared at boot. Register from `lib/`; registering from reloadable `app/` code with a callable route raises on the second load, because callables are compared by object identity.

## Browser demo

The dummy host app in `test/dummy/` is the browser-facing demo. `test/dummy/config/initializers/recording_studio_navigation.rb` registers example destinations the way an addon would, including a mounted Root Switchable route, and the home page renders them in a table with All / Admin / Sensitive filters and a request-time route column.

## Quick start

### Cursor Cloud Agent

A Cloud Agent boots this repo into a ready-to-use dev environment with no manual steps. The setup lives in `.cursor/`:

- `install.sh` provisions Ruby (pinned by `.ruby-version`), PostgreSQL 16, all gems, the seeded dummy database, and compiled CSS at build time, then fetches Recording Studio skills.
- `start.sh` starts PostgreSQL on every boot.
- `environment.json` runs the `rails-server` and `tailwind-watch` terminals and exposes port 3000.

Open port 3000 and sign in at `/users/sign_in`. No environment variables are required. The dummy app's `database.yml` defaults match the provisioned PostgreSQL cluster.

### GitHub Codespaces

1. Click **Code** → **Codespaces** → **Create codespace**
2. Wait for setup to complete
3. Run:
   ```bash
   cd test/dummy
   bin/rails db:setup
   bin/dev
   ```
4. Open port 3000. The navigation demo is at `/`, and sign-in is at `/users/sign_in`.

### Login credentials

| Field    | Value             |
|----------|-------------------|
| Email    | admin@admin.com   |
| Password | Password          |

The login form is prefilled with these credentials for fast access.

### Useful routes

- `/` is the navigation demo page (`?filter=all`, `?filter=admin`, or `?filter=sensitive`).
- `/users/sign_in` is the Devise sign-in page.
- `/recording_studio` redirects to `/`. The mounted Recording Studio engine stays data and API focused.
- `/recording_studio_root_switchable/v1/root_switch` is the mounted path the demo's mounted destination resolves to.
- `/docs/install`, `/docs/config`, `/docs/recordable_types`, `/docs/recordings_tree`, `/docs/gem_views`, and `/docs/methods` are dummy-only starter pages.

## Tests

```bash
bundle exec rake test        # registry suite, no Rails boot
bundle exec rake test:dummy  # dummy host app, including route resolution
bundle exec rake test:all    # both, the way CI runs them
```

The registry suite calls the public API and asserts literal results. Because the registry is one process-wide object, tests swap the registry ivar in `setup` and restore it in `teardown`; see `test/navigation/registry_isolation.rb`.

## Tech stack

| Component       | Version |
|-----------------|---------|
| Ruby            | 3.3+    |
| Rails           | 8.1+    |
| PostgreSQL      | 16      |
| TailwindCSS     | 4       |
| RecordingStudio | 4.x (`~> 4.2` in the gemspec; dummy GitHub tag `v4.2.0`) |
| Accessible      | dummy GitHub tag `v0.9.1` |
| Root Switchable | dummy GitHub tag `v0.5.0` |
| FlatPack        | dummy GitHub tag `v0.1.177` |
| Devise          | latest  |

The dummy Gemfile keeps `github:` sources so Bundler can fetch those gems. The gemspec pins `recording_studio` to `~> 4.2` so host apps declare the core dependency even when GitHub is the fetch source.

## Documentation

The gem template documentation this addon grew out of is preserved in `docs/gem_template/` as architectural reference material. Use it as background on engine conventions; this README and the dummy app are the source of truth for how the navigation registry works.
