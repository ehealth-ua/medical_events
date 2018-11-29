defmodule SecondaryEventsConsumer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias SecondaryEventsConsumer.Kafka.Consumer

  def start(_type, _args) do
    consumer_group_opts = [
      # setting for the ConsumerGroup
      heartbeat_interval: 1_000,
      # this setting will be forwarded to the GenConsumer
      commit_interval: 1_000
    ]

    gen_consumer_impl = Consumer
    consumer_group_name = "secondary_events_group"
    topic_names = ["secondary_events", "update_job_events"]

    # List all child processes to be supervised
    children = [
      %{
        id: KafkaEx.ConsumerGroup,
        start:
          {KafkaEx.ConsumerGroup, :start_link,
           [
             gen_consumer_impl,
             consumer_group_name,
             topic_names,
             consumer_group_opts
           ]},
        type: :supervisor
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SecondaryEventsConsumer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
