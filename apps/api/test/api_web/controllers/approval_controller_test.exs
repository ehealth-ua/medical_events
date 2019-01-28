defmodule Api.Web.ApprovalControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase
  import Mox
  import Core.Expectations.MPIExpectations
  import Core.Expectations.OTPVerificationExpectations

  alias Core.Approval
  alias Core.Patient
  alias Core.Patients

  describe "create approval" do
    test "patient not found", %{conn: conn} do
      assert conn
             |> post(approval_path(conn, :create, UUID.uuid4()), build_request_params(:resources))
             |> json_response(404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      assert conn
             |> post(approval_path(conn, :create, patient_id), build_request_params(:resources))
             |> json_response(409)
    end

    test "invalid request params", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      resp =
        conn
        |> post(approval_path(conn, :create, patient_id), build_request_params(:invalid))
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" =>
                         "expected exactly one of the schemata to match, but the schemata at the following indexes did: 0, 1",
                       "params" => [],
                       "rule" => "schemata"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.access_level",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "value is not allowed in enum",
                       "params" => ["read"],
                       "rule" => "inclusion"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.granted_to.identifier.type.coding.[0].code",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "value is not allowed in enum",
                       "params" => ["employee"],
                       "rule" => "inclusion"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "success approval create with resources request param", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      assert resp =
               conn
               |> post(approval_path(conn, :create, patient_id), build_request_params(:resources))
               |> json_response(202)

      assert %{
               "data" => %{
                 "id" => _,
                 "inserted_at" => _,
                 "status" => "pending",
                 "updated_at" => _
               }
             } = resp
    end

    test "success approval create with service_request request param", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      assert resp =
               conn
               |> post(approval_path(conn, :create, patient_id), build_request_params(:service_request))
               |> json_response(202)

      assert %{
               "data" => %{
                 "id" => _,
                 "inserted_at" => _,
                 "status" => "pending",
                 "updated_at" => _
               }
             } = resp
    end
  end

  describe "verify approval" do
    test "success verify approval", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      approval = insert(:approval, patient_id: patient_id_hash)
      id = to_string(approval._id)

      expect_person(patient_id)
      expect_otp_verification_complete(:ok)

      resp =
        conn
        |> patch(approval_path(conn, :verify, patient_id, id), %{"code" => "test"})
        |> json_response(200)
        |> Map.get("data")

      assert resp == %{}
    end

    test "patient not found", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      approval = insert(:approval)
      id = to_string(approval._id)

      assert conn
             |> patch(approval_path(conn, :verify, UUID.uuid4(), id), %{"code" => "test"})
             |> json_response(404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      approval = insert(:approval)
      id = to_string(approval._id)

      resp =
        conn
        |> patch(approval_path(conn, :verify, patient_id, id), %{"code" => "test"})
        |> json_response(409)

      assert %{
               "message" => "Person is not active",
               "type" => "request_conflict"
             } = resp["error"]
    end

    test "approval not found", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      assert conn
             |> patch(approval_path(conn, :verify, patient_id, UUID.uuid4()), %{"code" => "test"})
             |> json_response(404)
    end

    test "approval status is not NEW", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      approval = insert(:approval, status: Approval.status(:active))
      id = to_string(approval._id)

      resp =
        conn
        |> patch(approval_path(conn, :verify, patient_id, id), %{"code" => "test"})
        |> json_response(409)

      assert %{
               "message" => "Approval in status active can not be verified",
               "type" => "request_conflict"
             } = resp["error"]
    end

    test "verification phone_number is not found", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      approval = insert(:approval, patient_id: patient_id_hash)
      id = to_string(approval._id)

      expect_person(patient_id)
      expect_otp_verification_complete(:not_found)

      resp =
        conn
        |> patch(approval_path(conn, :verify, patient_id, id), %{"code" => "test"})
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.otp",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Invalid verification code",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "verification code is invalid", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      approval = insert(:approval, patient_id: patient_id_hash)
      id = to_string(approval._id)

      expect_person(patient_id)
      expect_otp_verification_complete(:error)

      resp =
        conn
        |> patch(approval_path(conn, :verify, patient_id, id), %{"code" => "test"})
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.otp",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Invalid verification code",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "success verify approval when person's auth method is not OTP", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      approval = insert(:approval, patient_id: patient_id_hash)
      id = to_string(approval._id)

      expect_person_offline_auth_method(patient_id)

      resp =
        conn
        |> patch(approval_path(conn, :verify, patient_id, id), %{"code" => "test"})
        |> json_response(200)
        |> Map.get("data")

      assert resp == %{}
    end
  end

  describe "resend approval" do
    test "patient not found", %{conn: conn} do
      assert conn
             |> post(approval_path(conn, :resend, UUID.uuid4(), UUID.uuid4()))
             |> json_response(404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      assert conn
             |> post(approval_path(conn, :resend, patient_id, UUID.uuid4()))
             |> json_response(409)
    end

    test "approval not found", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      assert conn
             |> post(approval_path(conn, :resend, patient_id, UUID.uuid4()))
             |> json_response(404)
    end

    test "success approval resend", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      approval = insert(:approval, patient_id: patient_id_hash)
      id = to_string(approval._id)

      assert resp =
               conn
               |> post(approval_path(conn, :resend, patient_id, id))
               |> json_response(202)

      assert %{
               "data" => %{
                 "id" => _,
                 "inserted_at" => _,
                 "status" => "pending",
                 "updated_at" => _
               }
             } = resp
    end
  end

  defp build_request_params(:resources) do
    episodes = build_episode_references()

    to_map(%{
      resources: episodes,
      granted_to:
        build(:reference,
          identifier:
            build(:identifier,
              value: UUID.uuid4(),
              type: codeable_concept_coding(system: "eHealth/resources", code: "employee")
            )
        ),
      access_level: Approval.access_level(:read)
    })
  end

  defp build_request_params(:service_request) do
    episodes = build_episode_references()

    service_request = insert(:service_request, permitted_episodes: episodes)
    service_request_id = to_string(service_request._id)

    to_map(%{
      service_request:
        build(:reference,
          identifier:
            build(:identifier,
              value: service_request_id,
              type: codeable_concept_coding(system: "eHealth/resources", code: "service_request")
            )
        ),
      granted_to:
        build(:reference,
          identifier:
            build(:identifier,
              value: UUID.uuid4(),
              type: codeable_concept_coding(system: "eHealth/resources", code: "employee")
            )
        ),
      access_level: Approval.access_level(:read)
    })
  end

  defp build_request_params(:invalid) do
    episodes = build_episode_references()
    service_request = build(:service_request, permitted_episodes: episodes)
    service_request_id = to_string(service_request._id)

    to_map(%{
      resources: episodes,
      service_request:
        build(:reference,
          identifier:
            build(:identifier,
              value: service_request_id,
              type: codeable_concept_coding(system: "eHealth/resources", code: "service_request")
            )
        ),
      granted_to:
        build(:reference,
          identifier:
            build(:identifier,
              value: "TEST",
              type: codeable_concept_coding(system: "eHealth/resources", code: "mpi-hash")
            )
        ),
      access_level: "write"
    })
  end

  defp build_episode_references() do
    [
      build(:reference,
        identifier:
          build(:identifier,
            value: UUID.uuid4(),
            type: codeable_concept_coding(system: "eHealth/resources", code: "episode_of_care")
          )
      )
    ]
  end

  defp to_map(nil), do: nil

  defp to_map(%{__struct__: _} = value) do
    value
    |> Map.from_struct()
    |> Map.drop(~w(__meta__ __validations__ display_value text)a)
    |> Enum.map(fn {k, v} ->
      if is_atom(k) do
        {Atom.to_string(k), to_map(v)}
      else
        {k, to_map(v)}
      end
    end)
    |> Enum.into(%{})
  end

  defp to_map(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} ->
      if is_atom(k) do
        {Atom.to_string(k), to_map(v)}
      else
        {k, to_map(v)}
      end
    end)
    |> Enum.into(%{})
  end

  defp to_map(value) when is_list(value), do: Enum.map(value, &to_map/1)
  defp to_map(value), do: value
end