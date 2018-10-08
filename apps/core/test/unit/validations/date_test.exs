defmodule Core.Validations.DateTest do
  @moduledoc false

  use ExUnit.Case
  alias Core.Validators.Date, as: DateValidator

  test "validate_expiration" do
    add_to_today = &Date.add(Date.utc_today(), &1)

    test_data_set = [
      # Today is late
      {add_to_today.(0), 0, {:error, ""}},

      # Positive values are always in future
      {add_to_today.(1), 0, :ok},
      {add_to_today.(1), 1, :ok},
      {add_to_today.(10), 20, :ok},

      # Dates in past
      {~D[1990-01-01], 10, {:error, ""}},
      {add_to_today.(-1), 10, :ok},
      {add_to_today.(-9), 10, :ok},
      {add_to_today.(-10), 10, {:error, ""}},
      {add_to_today.(-20), 15, {:error, ""}},
      {add_to_today.(-100), 150 * 365, :ok}
    ]

    Enum.map(test_data_set, fn
      {date, days_passed, :ok} ->
        assert :ok == DateValidator.validate_expiration(date, days_passed)

      {date, days_passed, _} ->
        assert {:error, _} = DateValidator.validate_expiration(date, days_passed)
    end)
  end
end
