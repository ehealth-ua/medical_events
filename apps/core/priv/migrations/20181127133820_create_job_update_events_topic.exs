defmodule Core.Migrations.CreateJobUpdateEventsTopic do
  @moduledoc false

  def change do
    Application.ensure_started(:kafka_ex)

    request = %{
      topic: "job_update_events",
      num_partitions: 4,
      replication_factor: 3,
      replica_assignment: [],
      config_entries: []
    }

    KafkaEx.create_topics([request], timeout: 2000)
  end
end
