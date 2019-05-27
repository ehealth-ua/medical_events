defmodule PersonConsumer.Kafka.PersonEventConsumerTest do
  @moduledoc false

  use Core.ModelCase
  import Mox
  alias Core.Patient
  alias Core.Patients
  alias PersonConsumer.Kafka.PersonEventConsumer

  describe "consume" do
    test "success consume" do
      id = UUID.uuid4()
      id_hash = Patients.get_pk_hash(id)
      status_active = Patient.status(:active)

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [
                   %{"collection" => "patients", "operation" => "upsert_one", "filter" => filter, "set" => set}
                 ]
               } = Jason.decode!(args)

        assert %{"_id" => ^id_hash} = filter |> Base.decode64!() |> BSON.decode()
        assert %{"$set" => %{"status" => ^status_active}} = set |> Base.decode64!() |> BSON.decode()

        :ok
      end)

      assert :ok == PersonEventConsumer.consume(%{"id" => id, "status" => status_active, "updated_by" => id})
    end

    test "update existing person" do
      id = UUID.uuid4()
      id_hash = Patients.get_pk_hash(id)
      %{_id: id_hash} = patient = insert(:patient, _id: id_hash)
      status_inactive = Patient.status(:inactive)

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [
                   %{"collection" => "patients", "operation" => "upsert_one", "filter" => filter, "set" => set}
                 ]
               } = Jason.decode!(args)

        assert %{"_id" => ^id_hash} = filter |> Base.decode64!() |> BSON.decode()
        assert %{"$set" => %{"status" => ^status_inactive}} = set |> Base.decode64!() |> BSON.decode()

        :ok
      end)

      assert :ok ==
               PersonEventConsumer.consume(%{
                 "id" => id,
                 "updated_by" => patient.updated_by,
                 "status" => status_inactive
               })
    end

    test "invalid status" do
      id = UUID.uuid4()
      id_hash = Patients.get_pk_hash(id)
      assert :ok == PersonEventConsumer.consume(%{"id" => id, "status" => "invalid"})
      refute Mongo.find_one(Patient.collection(), %{"_id" => id_hash})
    end
  end
end
