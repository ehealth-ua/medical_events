defmodule Core.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Core.Repo

  def start(_type, _args) do
    import Supervisor.Spec

    # List all child processes to be supervised
    children = [
      worker(Core.Validators.Cache, []),
      worker(Mongo, [[name: :mongo, url: Application.get_env(:core, :mongo)[:url], pool: DBConnection.Poolboy]])
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Core.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
