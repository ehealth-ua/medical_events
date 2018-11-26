defmodule Core.RpcTest do
  @moduledoc false

  use ExUnit.Case
  import Core.Factories
  import Mox

  alias Core.Patients
  alias Core.Rpc

  test "get encounter status by id" do
    expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
    encounter_1 = build(:encounter)
    encounter_2 = build(:encounter, status: "entered_in_error")
    patient_id = UUID.uuid4()
    patient_id_hash = Patients.get_pk_hash(patient_id)

    insert(
      :patient,
      _id: patient_id_hash,
      encounters: %{
        UUID.binary_to_string!(encounter_1.id.binary) => encounter_1,
        UUID.binary_to_string!(encounter_2.id.binary) => encounter_2
      }
    )

    assert {:ok, "finished"} == Rpc.encounter_status_by_id(patient_id, UUID.binary_to_string!(encounter_1.id.binary))

    assert {:ok, "entered_in_error"} ==
             Rpc.encounter_status_by_id(patient_id, UUID.binary_to_string!(encounter_2.id.binary))

    refute Rpc.encounter_status_by_id(patient_id, UUID.uuid4())
  end
end
