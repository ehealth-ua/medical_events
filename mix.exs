defmodule MedicalEvents.Umbrella.Mixfile do
  use Mix.Project

  @version "3.1.0"
  def project do
    [
      version: @version,
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        filter_prefix: "*.Rpc"
      ]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps folder
  defp deps do
    [
      {:distillery, "~> 2.0", runtime: false, override: true},
      {:excoveralls, "~> 0.10.6", only: [:dev, :test]},
      {:credo, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:git_ops, "~> 0.6.0", only: [:dev]}
    ]
  end
end
