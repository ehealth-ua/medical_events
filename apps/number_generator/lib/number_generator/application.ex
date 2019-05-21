defmodule NumberGenerator.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = []

    children =
      if Application.get_env(:number_generator, :env) == :prod do
        children ++
          [
            {Cluster.Supervisor,
             [Application.get_env(:number_generator, :topologies), [name: NumberGenerator.ClusterSupervisor]]}
          ]
      else
        children
      end

    opts = [strategy: :one_for_one, name: NumberGenerator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
