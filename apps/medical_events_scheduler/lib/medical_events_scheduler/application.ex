defmodule MedicalEventsScheduler.Application do
  @moduledoc false

  use Application
  alias MedicalEventsScheduler.Jobs.ServiceRequestAutoexpiration
  alias MedicalEventsScheduler.Worker

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {Worker, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MedicalEventsScheduler.Supervisor]
    result = Supervisor.start_link(children, opts)
    Worker.create_jobs()
    result
  end
end
