defmodule PersonConsumer.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    Application.put_env(:kaffe, :consumer, Application.get_env(:person_consumer, :kaffe_consumer))

    children = [
      %{
        id: Kaffe.GroupMemberSupervisor,
        start: {Kaffe.GroupMemberSupervisor, :start_link, []},
        type: :supervisor
      }
    ]

    opts = [strategy: :one_for_one, name: PersonConsumer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
