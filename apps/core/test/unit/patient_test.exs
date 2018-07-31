defmodule Core.PatientTest do
  @moduledoc false

  use Core.ModelCase

  describe "test create patient" do
    test "success create patient" do
      patient = build(:patient)

      Core.Mongo.insert_one(patient)
      |> IO.inspect()
    end
  end
end
