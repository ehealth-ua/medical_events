defmodule Core.ObservationTest do
  @moduledoc false

  use Core.ModelCase
  alias Core.Repo

  describe "test create patient" do
    test "success create patient" do
      insert(:patient)
    end
  end
end
