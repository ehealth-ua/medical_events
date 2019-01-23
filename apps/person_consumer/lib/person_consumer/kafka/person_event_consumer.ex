defmodule PersonConsumer.Kafka.PersonEventConsumer do
  @moduledoc false

  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients
  require Logger

  @status_active Patient.status(:active)
  @status_inactive Patient.status(:inactive)

  def handle_message(%{offset: offset, value: value}) do
    value = :erlang.binary_to_term(value)
    Logger.debug(fn -> "message: " <> inspect(value) end)
    Logger.info(fn -> "offset: #{offset}" end)
    :ok = consume(value)
  end

  def consume(%{"id" => person_id, "status" => status, "updated_by" => updated_by})
      when status in [@status_active, @status_inactive] do
    Mongo.update_one(
      Patient.metadata().collection,
      %{"_id" => Patients.get_pk_hash(person_id)},
      %{
        "$set" => %{"status" => status, "updated_by" => updated_by},
        "$setOnInsert" => %{
          "visits" => %{},
          "episodes" => %{},
          "encounters" => %{},
          "immunizations" => %{},
          "allergy_intolerances" => %{},
          "risk_assessments" => %{},
          "status_history" => []
        }
      },
      upsert: true
    )

    :ok
  end

  def consume(value) do
    Logger.warn(fn -> "unknown kafka event: #{inspect(value)}" end)
    :ok
  end
end
