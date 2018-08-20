defmodule AuditLogConsumer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @consumer_group_name "mongo_event_group"
  @topic_names ~w(mongo_events)

  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    alias AuditLogConsumer.Kafka.MongoEventConsumer

    consumer_group_opts = [
      # setting for the ConsumerGroup
      heartbeat_interval: 1_000,
      # this setting will be forwarded to the GenConsumer
      commit_interval: 1_000
    ]

    # List all child processes to be supervised
    children = [
      supervisor(KafkaEx.ConsumerGroup, [
        MongoEventConsumer,
        @consumer_group_name,
        @topic_names,
        consumer_group_opts
      ])
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MongoEventConsumer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
