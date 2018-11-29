defmodule Core.Migrations.CreateSecondaryEventsTopic do
  @moduledoc false

  def change do
    Application.ensure_started(:kafka_ex)

    request = %{
      topic: "secondary_events",
      num_partitions: 4,
      replication_factor: 1,
      replica_assignment: [],
      config_entries: []
    }

    KafkaEx.create_topics([request], timeout: 2000)
  end
end
