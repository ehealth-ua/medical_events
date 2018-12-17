use Mix.Config

config :api, ApiWeb.Endpoint,
  http: [port: {:system, "PORT", 4000}],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: []

config :phoenix, :stacktrace_depth, 20
