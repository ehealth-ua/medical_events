defmodule Api.Mixfile do
  use Mix.Project

  def project do
    [
      app: :api,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.8.1",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Api.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:core, in_umbrella: true},
      {:confex_config_provider, "~> 0.1.0"},
      {:phoenix, "~> 1.4.0"},
      {:phoenix_pubsub, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:plug, "~> 1.7"},
      {:jason, "~> 1.1"},
      {:confex, "~> 3.3"},
      {:scrivener, "~> 2.5"},
      {:eview, "~> 0.15.0"},
      {:libcluster, "~> 3.0",
       git: "https://github.com/AlexKovalevych/libcluster.git", branch: "fix_kubernetes_strategy"}
    ]
  end

  defp aliases do
    [
      "ecto.setup": []
    ]
  end
end
