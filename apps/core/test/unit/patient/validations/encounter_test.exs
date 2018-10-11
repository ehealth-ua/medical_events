defmodule Core.Patients.Encounters.ValidationsTest do
  @moduledoc false

  use ExUnit.Case

  import Core.Expectations.IlExpectations
  import Mox

  alias Core.Patients.Encounters.Validations, as: EncounterValidation

  setup :verify_on_exit!

  test "validate signature is off" do
    Application.put_env(:core, :digital_signarure_enabled?, false)

    assert :ok == EncounterValidation.validate_signatures(%{}, UUID.uuid4(), UUID.uuid4(), UUID.uuid4())

    Application.put_env(:core, :digital_signarure_enabled?, true)
  end

  test "success" do
    employee_id = UUID.uuid4()
    user_id = UUID.uuid4()
    client_id = UUID.uuid4()

    drfo = String.replace(UUID.uuid4(), "-", "")
    expect_employee_users(drfo, user_id)

    assert :ok == EncounterValidation.validate_signatures(%{"drfo" => drfo}, employee_id, user_id, client_id)
  end

  test "invalid user_id" do
    drfo = UUID.uuid4()
    expect_employee_users(drfo, UUID.uuid4())

    assert {:error, "Employee is not performer of encouner"} ==
             EncounterValidation.validate_signatures(%{"drfo" => drfo}, UUID.uuid4(), UUID.uuid4(), UUID.uuid4())
  end

  test "invalid drfo" do
    user_id = UUID.uuid4()
    expect_employee_users(UUID.uuid4(), user_id)

    assert {:error, "Does not match the signer drfo"} =
             EncounterValidation.validate_signatures(%{"drfo" => UUID.uuid4()}, UUID.uuid4(), user_id, UUID.uuid4())
  end
end
