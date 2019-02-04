defmodule Api.Rpc.RpcTest do
  @moduledoc false

  use ExUnit.Case
  import Core.Factories
  import Mox

  alias Api.Rpc
  alias Core.Patients

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

  describe "episode_by_id/2" do
    test "episode not found" do
      refute Rpc.episode_by_id(UUID.uuid4(), UUID.uuid4())
    end

    test "episode was found" do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      episode_1 = build(:episode)
      episode_2 = build(:episode)
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      episode_id = UUID.binary_to_string!(episode_1.id.binary)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{
          episode_id => episode_1,
          UUID.binary_to_string!(episode_2.id.binary) => episode_2
        }
      )

      assert {:ok, %{id: ^episode_id}} = Rpc.episode_by_id(patient_id, episode_id)
    end
  end

  describe "approvals_by_episode/3" do
    test "success get approvals by episode" do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      approval = insert(:approval, patient_id: patient_id_hash)
      insert(:approval, patient_id: patient_id_hash)
      [%{identifier: %{value: episode_id}}] = approval.granted_resources
      approval_id = to_string(approval._id)

      approvals =
        Rpc.approvals_by_episode(patient_id, [to_string(approval.granted_to.identifier.value)], to_string(episode_id))

      assert [%{id: ^approval_id}] = approvals
    end
  end
end
