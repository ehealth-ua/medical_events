# Import all plugins from `rel/plugins`
# They can then be used by adding `plugin MyPlugin` to
# either an environment, or release definition, where
# `MyPlugin` is the name of the plugin module.
~w(rel plugins *.exs)
|> Path.join()
|> Path.wildcard()
|> Enum.map(&Code.eval_file(&1))

use Mix.Releases.Config,
  # This sets the default release built by `mix release`
  default_release: :default,
  # This sets the default environment used by `mix release`
  default_environment: :default

environment :default do
  set(pre_start_hooks: "bin/hooks/")
  set(dev_mode: false)
  set(include_erts: true)
  set(include_src: false)

  set(
    overlays: [
      {:template, "rel/templates/vm.args.eex", "releases/<%= release_version %>/vm.args"}
    ]
  )
end

# You may define one or more releases in this file.
# If you have not set a default release, or selected one
# when running `mix release`, the first release in the file
# will be used by default

release :medical_events_api do
  set(version: current_version(:api))

  set(
    applications: [
      :runtime_tools,
      api: :permanent,
      core: :permanent
    ]
  )

  set(config_providers: [ConfexConfigProvider])
end

release :event_consumer do
  set(version: current_version(:event_consumer))

  set(
    applications: [
      :runtime_tools,
      event_consumer: :permanent,
      core: :permanent
    ]
  )

  set(config_providers: [ConfexConfigProvider])
end

release :person_consumer do
  set(version: current_version(:person_consumer))

  set(
    applications: [
      :runtime_tools,
      person_consumer: :permanent,
      core: :permanent
    ]
  )

  set(config_providers: [ConfexConfigProvider])
end

release :number_generator do
  set(version: current_version(:number_generator))

  set(
    applications: [
      :runtime_tools,
      number_generator: :permanent,
      core: :permanent
    ]
  )

  set(config_providers: [ConfexConfigProvider])
end

release :medical_events_scheduler do
  set(version: current_version(:medical_events_scheduler))

  set(
    applications: [
      :runtime_tools,
      medical_events_scheduler: :permanent,
      core: :permanent
    ]
  )

  set(config_providers: [ConfexConfigProvider])
end
