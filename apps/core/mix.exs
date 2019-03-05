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
      elixir: "~> 1.8.1",
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
      reset: ["drop", "migrate"],
      test: ["reset", "test"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:kube_rpc, git: "https://github.com/edenlabllc/kube_rpc.git"},
      {:confex, "~> 3.4"},
      {:ehealth_logger, git: "https://github.com/edenlabllc/ehealth_logger.git"},
      {:elixir_uuid, "~> 1.2"},
      {:eview, "~> 0.14.0"},
      {:httpoison, "~> 1.2"},
      {:iteraptor, "~> 1.3.2"},
      {:jason, "~> 1.1"},
      {:jvalid, "~> 0.7.0"},
      {:kaffe, "~> 1.11"},
      {:mongodb, "~> 0.4.6"},
      {:poolboy, "~> 1.5"},
      {:redix, "~> 0.7.1"},
      {:scrivener, "~> 2.5"},
      {:translit, "~> 0.1.0"},
      {:vex, "~> 0.8.0"},
      {:mox, "~> 0.4.0", only: :test},
      {:ex_machina, "~> 2.2", only: :test}
    ]
  end
end
