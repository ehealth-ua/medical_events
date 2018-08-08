defmodule PersonConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :person_consumer,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PersonConsumer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:toml, "~> 0.3.0"},
      {:kafka_ex, "~> 0.8.3"},
      {:core, in_umbrella: true}
    ]
  end

  defp aliases do
    [
      "ecto.setup": []
    ]
  end
end
