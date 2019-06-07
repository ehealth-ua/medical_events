defmodule Core.Patients.Encounters.ValidationsTest do
  @moduledoc false

  use ExUnit.Case

  import Core.Expectations.IlExpectations
  import Mox

  alias Core.DigitalSignature
  alias Core.Patients.Encounters.Validations, as: EncounterValidation

  setup :verify_on_exit!

  test "validate signature is off" do
    ds_config = Confex.fetch_env!(:core, DigitalSignature)
    Application.put_env(:core, DigitalSignature, Keyword.merge(ds_config, enabled: false))

    assert :ok == EncounterValidation.validate_signatures(%{}, UUID.uuid4(), UUID.uuid4(), UUID.uuid4())

    Application.put_env(:core, DigitalSignature, Keyword.merge(ds_config, enabled: true))
  end

  test "success" do
    employee_id = UUID.uuid4()
    user_id = UUID.uuid4()
    client_id = UUID.uuid4()

    drfo = String.replace(UUID.uuid4(), "-", "")
    expect_employee_users(drfo, client_id, user_id)

    assert :ok == EncounterValidation.validate_signatures(%{"drfo" => drfo}, employee_id, user_id, client_id)
  end

  test "invalid user_id" do
    drfo = UUID.uuid4()
    client_id = UUID.uuid4()
    expect_employee_users(drfo, client_id, UUID.uuid4())

    assert {:error, "Employee is not performer of encounter", 409} ==
             EncounterValidation.validate_signatures(%{"drfo" => drfo}, UUID.uuid4(), UUID.uuid4(), client_id)
  end

  test "invalid drfo" do
    user_id = UUID.uuid4()
    client_id = UUID.uuid4()
    expect_employee_users(UUID.uuid4(), client_id, user_id)

    assert {:error, "Does not match the signer drfo", 409} =
             EncounterValidation.validate_signatures(%{"drfo" => UUID.uuid4()}, UUID.uuid4(), user_id, UUID.uuid4())
  end

  test "invalid employee legal entity id" do
    employee_id = UUID.uuid4()
    user_id = UUID.uuid4()
    client_id = UUID.uuid4()
    invalid_legal_entity_id = UUID.uuid4()
    drfo = UUID.uuid4()

    expect_employee_users(drfo, invalid_legal_entity_id, user_id)

    assert {:error, "Performer does not belong to current legal entity", 409} ==
             EncounterValidation.validate_signatures(%{"drfo" => drfo}, employee_id, user_id, client_id)
  end
end
