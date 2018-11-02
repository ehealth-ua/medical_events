defmodule Core.Migrations.CreatePersonEventsTopic do
  @moduledoc false

  def change do
    Application.ensure_started(:kafka_ex)

    request = %{
      topic: "person_events",
      num_partitions: 4,
      replication_factor: 1,
      replica_assignment: [],
      config_entries: []
    }

    KafkaEx.create_topics([request], timeout: 2000)
  end
end
