defmodule Core.MixProject do
  @moduledoc false

  use Mix.Project

  def project do
    [
      app: :core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      preferred_cli_env: [coveralls: :test],
      test_coverage: [tool: ExCoveralls],
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Core.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      reset: [
        "xandra.drop",
        "xandra.create",
        "xandra.migrate"
      ],
      test: [
        "xandra.create",
        "xandra.migrate",
        "test"
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 2.1"},
      {:mongodb_ecto, "~> 0.2.0"},
      {:poolboy, "~> 1.5"},
      {:ecto_logger_json, git: "https://github.com/edenlabllc/ecto_logger_json.git", branch: "query_params"},
      {:plug_logger_json, "~> 0.6.0"},
      {:jason, "~> 1.1"},
      {:confex, "~> 3.3"},
      {:ex_machina, "~> 2.2"}
    ]
  end
end
