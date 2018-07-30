defmodule Core.PatientTest do
  @moduledoc false

  use Core.ModelCase

  describe "test create patient" do
    test "success create patient" do
      insert(:patient)
    end
  end
end
