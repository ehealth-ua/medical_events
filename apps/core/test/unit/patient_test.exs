defmodule Core.PatientTest do
  @moduledoc false

  use Core.ModelCase
  import Mox

  describe "test create patient" do
    test "success create patient" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      patient = build(:patient)
      assert {:ok, _} = Core.Mongo.insert_one(patient)
    end
  end
end
