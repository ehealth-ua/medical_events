defmodule SecondaryEventsConsumer.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    Application.put_env(
      :kaffe,
      :consumer,
      Application.get_env(:secondary_events_consumer, :kaffe_consumer)
    )

    children = [
      %{
        id: Kaffe.Consumer,
        start: {Kaffe.Consumer, :start_link, []}
      }
    ]

    opts = [strategy: :one_for_one, name: SecondaryEventsConsumer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
