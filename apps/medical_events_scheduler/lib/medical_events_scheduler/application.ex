defmodule MedicalEventsScheduler.Application do
  @moduledoc false

  use Application
  alias MedicalEventsScheduler.Worker

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {Worker, []}
    ]

    children =
      if Application.get_env(:medical_events_scheduler, :env) == :prod do
        children ++
          [
            {Cluster.Supervisor,
             [
               Application.get_env(:medical_events_scheduler, :topologies),
               [name: MedicalEventsScheduler.ClusterSupervisor]
             ]}
          ]
      else
        children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MedicalEventsScheduler.Supervisor]
    result = Supervisor.start_link(children, opts)
    Worker.create_jobs()
    result
  end
end
