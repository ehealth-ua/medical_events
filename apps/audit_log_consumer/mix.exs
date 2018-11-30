defmodule AuditLogConsumer.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :audit_log_consumer,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AuditLogConsumer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:kafka_ex, git: "https://github.com/kafkaex/kafka_ex.git", branch: "master"},
      {:confex_config_provider, "~> 0.1.0"},
      {:core, in_umbrella: true}
    ]
  end
end
