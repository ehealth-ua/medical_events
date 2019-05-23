defmodule MedicalEventsScheduler.MixProject do
  use Mix.Project

  def project do
    [
      app: :medical_events_scheduler,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.8.1",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MedicalEventsScheduler.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:quantum, "~> 2.3"},
      {:confex_config_provider, "~> 0.1.0"},
      {:core, in_umbrella: true}
    ]
  end

  defp aliases do
    [
      "ecto.setup": []
    ]
  end
end
