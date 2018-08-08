defmodule PersonConsumer.Kafka.PersonEventConsumerTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Patient
  alias PersonConsumer.Kafka.PersonEventConsumer

  describe "consume" do
    test "success consume" do
      id = UUID.uuid4()
      status_active = Patient.status(:active)
      assert :ok == PersonEventConsumer.consume(%{"id" => id, "status" => status_active})
      assert %{"_id" => ^id, "status" => ^status_active} = Mongo.find_one(Patient.metadata().collection, %{"_id" => id})
    end

    test "update existing person" do
      patient = build(:patient)
      id = patient._id
      assert {:ok, _} = Mongo.insert_one(patient)
      status_inactive = Patient.status(:inactive)
      assert :ok == PersonEventConsumer.consume(%{"id" => id, "status" => status_inactive})

      assert %{"_id" => ^id, "status" => ^status_inactive} =
               Mongo.find_one(Patient.metadata().collection, %{"_id" => id})
    end

    test "invalid status" do
      id = UUID.uuid4()
      assert :ok == PersonEventConsumer.consume(%{"id" => id, "status" => "invalid"})
      refute Mongo.find_one(Patient.metadata().collection, %{"_id" => id})
    end
  end
end
