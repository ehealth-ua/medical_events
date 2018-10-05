defmodule Core.Validations.DateTest do
  @moduledoc false

  use ExUnit.Case
  alias Core.Validators.Date, as: DateValidator

  test "validate_expiration" do
    validate = &DateValidator.validate_expiration(&1, &2)
    add_to_today = &Date.add(Date.utc_today(), &1)

    test_data_set = [
      # Today is late
      {0, 0, {:error, ""}},

      # Positive values are always in future
      {1, 0, :ok},
      {1, 1, :ok},
      {10, 20, :ok},

      # Days in past
      {-1, 10, :ok},
      {-9, 10, :ok},
      {-10, 10, {:error, ""}},
      {-20, 15, {:error, ""}},
      {-100, 150 * 365, :ok}
    ]

    Enum.map(test_data_set, fn
      {days_count, days_passed, :ok} ->
        assert :ok == validate.(add_to_today.(days_count), days_passed)

      {days_count, days_passed, _} ->
        assert {:error, _} = validate.(add_to_today.(days_count), days_passed)
    end)
  end
end
