defmodule Core.Patients.Encounters.ValidationsTest do
  @moduledoc false

  use ExUnit.Case

  import Core.Expectations.IlExpectations
  import Mox

  alias Core.Microservices.DigitalSignature
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
    expect_employee_users(drfo, user_id)

    assert :ok == EncounterValidation.validate_signatures(%{"drfo" => drfo}, employee_id, user_id, client_id)
  end

  test "invalid user_id" do
    drfo = UUID.uuid4()
    expect_employee_users(drfo, UUID.uuid4())

    assert {:error, "Employee is not performer of encounter"} ==
             EncounterValidation.validate_signatures(%{"drfo" => drfo}, UUID.uuid4(), UUID.uuid4(), UUID.uuid4())
  end

  test "invalid drfo" do
    user_id = UUID.uuid4()
    expect_employee_users(UUID.uuid4(), user_id)

    assert {:error, "Does not match the signer drfo"} =
             EncounterValidation.validate_signatures(%{"drfo" => UUID.uuid4()}, UUID.uuid4(), user_id, UUID.uuid4())
  end

  test "invalid employee legal entity id" do
    employee_id = UUID.uuid4()
    user_id = UUID.uuid4()
    client_id = UUID.uuid4()
    invalid_legal_entity_id = UUID.uuid4()
    drfo = UUID.uuid4()

    expect(IlMock, :get_employee_users, fn employee_id, _ ->
      {:ok,
       %{
         "data" => %{
           "id" => employee_id,
           "legal_entity_id" => invalid_legal_entity_id,
           "party" => %{
             "tax_id" => drfo,
             "users" => [%{"user_id" => user_id}]
           }
         }
       }}
    end)

    assert {:error, "Performer does not belong to current legal entity"} ==
             EncounterValidation.validate_signatures(%{"drfo" => drfo}, employee_id, user_id, client_id)
  end
end
