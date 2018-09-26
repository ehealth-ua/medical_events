defmodule PersonConsumer.Kafka.PersonEventConsumerTest do
  @moduledoc false

  use Core.ModelCase
  import Mox
  alias Core.Patient
  alias Core.Patients
  alias PersonConsumer.Kafka.PersonEventConsumer

  describe "consume" do
    test "success consume" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      id = UUID.uuid4()
      id_hash = Patients.get_pk_hash(id)
      status_active = Patient.status(:active)
      assert :ok == PersonEventConsumer.consume(%{"id" => id, "status" => status_active, "updated_by" => id})

      assert %{"_id" => ^id_hash, "status" => ^status_active} =
               Mongo.find_one(Patient.metadata().collection, %{"_id" => id_hash})
    end

    test "update existing person" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      id = UUID.uuid4()
      id_hash = Patients.get_pk_hash(id)
      %{_id: id_hash} = patient = insert(:patient, _id: id_hash)
      status_inactive = Patient.status(:inactive)

      assert :ok ==
               PersonEventConsumer.consume(%{
                 "id" => id,
                 "updated_by" => patient.updated_by,
                 "status" => status_inactive
               })

      assert %{"_id" => ^id_hash, "status" => ^status_inactive} =
               Mongo.find_one(Patient.metadata().collection, %{"_id" => id_hash})
    end

    test "invalid status" do
      id = UUID.uuid4()
      id_hash = Patients.get_pk_hash(id)
      assert :ok == PersonEventConsumer.consume(%{"id" => id, "status" => "invalid"})
      refute Mongo.find_one(Patient.metadata().collection, %{"_id" => id_hash})
    end
  end
end
