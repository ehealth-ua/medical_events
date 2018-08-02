defmodule EventConsumer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    alias EventConsumer.Kafka.MedicalEventConsumer

    consumer_group_opts = [
      # setting for the ConsumerGroup
      heartbeat_interval: 1_000,
      # this setting will be forwarded to the GenConsumer
      commit_interval: 1_000
    ]

    gen_consumer_impl = MedicalEventConsumer
    consumer_group_name = "medical_event_group"
    topic_names = ["medical_events"]

    # List all child processes to be supervised
    children = [
      # Starts a worker by calling: EventConsumer.Worker.start_link(arg)
      # {EventConsumer.Worker, arg},
      supervisor(KafkaEx.ConsumerGroup, [
        gen_consumer_impl,
        consumer_group_name,
        topic_names,
        consumer_group_opts
      ])
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EventConsumer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
