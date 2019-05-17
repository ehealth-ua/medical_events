defmodule Api.Web.ServiceRequestControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase
  alias Core.Encryptor
  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients
  alias Core.ServiceRequest
  import Mox

  describe "list service requests" do
    test "patient not found", %{conn: conn} do
      conn = get(conn, service_request_path(conn, :index, UUID.uuid4(), UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = get(conn, service_request_path(conn, :index, patient_id, UUID.uuid4()))
      assert json_response(conn, 409)
    end

    test "additional params were sent", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      episode_id = UUID.uuid4()
      episode = build(:episode, id: episode_id)

      encounter =
        build(:encounter,
          episode: reference_coding(Mongo.string_to_uuid(episode_id), system: "eHealth/resources", code: "episode")
        )

      encounter_id = encounter.id

      insert(:patient,
        _id: patient_id_hash,
        episodes: %{episode_id => episode},
        encounters: %{to_string(encounter_id) => encounter}
      )

      search_params = %{
        "code" => UUID.uuid4(),
        "requisition" => "requisition",
        "status" => "active",
        "requester_legal_entity" => UUID.uuid4(),
        "used_by_legal_entity" => UUID.uuid4()
      }

      resp =
        conn
        |> get(service_request_path(conn, :index, patient_id, episode_id, search_params))
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.requester_legal_entity",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.requisition",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.used_by_legal_entity",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               }
             ] = resp["error"]["invalid"]
    end

    test "success list service_requests in context", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      episode_id = UUID.uuid4()
      episode = build(:episode, id: episode_id)

      encounter =
        build(:encounter,
          episode: reference_coding(Mongo.string_to_uuid(episode_id), system: "eHealth/resources", code: "episode")
        )

      encounter_id = encounter.id

      insert(:patient,
        _id: patient_id_hash,
        episodes: %{episode_id => episode},
        encounters: %{to_string(encounter_id) => encounter}
      )

      service_request =
        insert(:service_request,
          context: reference_coding(encounter_id, system: "eHealth/resources", code: "encounter"),
          subject: patient_id_hash
        )

      insert(:service_request, subject: patient_id_hash)
      id = to_string(service_request._id)
      conn = get(conn, service_request_path(conn, :index, patient_id, episode_id))

      assert response = json_response(conn, 200)
      assert [%{"id" => ^id}] = response["data"]
    end

    test "success list service_requests by code", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      episode_id = UUID.uuid4()
      episode = build(:episode, id: episode_id)

      encounter =
        build(:encounter,
          episode: reference_coding(Mongo.string_to_uuid(episode_id), system: "eHealth/resources", code: "episode")
        )

      encounter_id = encounter.id
      code = UUID.uuid4()

      insert(:patient,
        _id: patient_id_hash,
        episodes: %{episode_id => episode},
        encounters: %{to_string(encounter_id) => encounter}
      )

      service_request =
        insert(:service_request,
          context: reference_coding(encounter_id, system: "eHealth/resources", code: "encounter"),
          subject: patient_id_hash,
          code: reference_coding(Mongo.string_to_uuid(code), system: "eHealth/resources", code: "service")
        )

      insert(:service_request,
        context: reference_coding(encounter_id, system: "eHealth/resources", code: "encounter"),
        subject: patient_id_hash
      )

      id = to_string(service_request._id)
      conn = get(conn, service_request_path(conn, :index, patient_id, episode_id), %{"code" => code})

      assert response = json_response(conn, 200)
      assert [%{"id" => ^id}] = response["data"]
    end
  end

  describe "show service request" do
    test "patient not found", %{conn: conn} do
      conn = get(conn, service_request_path(conn, :show, UUID.uuid4(), UUID.uuid4(), UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = get(conn, service_request_path(conn, :show, patient_id, UUID.uuid4(), UUID.uuid4()))
      assert json_response(conn, 409)
    end

    test "service_request doesn't belong to episode", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      episode_id = UUID.uuid4()
      episode = build(:episode, id: episode_id)

      encounter =
        build(:encounter,
          episode: reference_coding(Mongo.string_to_uuid(episode_id), system: "eHealth/resources", code: "episode")
        )

      encounter_id = encounter.id

      insert(:patient,
        _id: patient_id_hash,
        episodes: %{episode_id => episode},
        encounters: %{to_string(encounter_id) => encounter}
      )

      service_request = insert(:service_request)
      id = to_string(service_request._id)

      conn = get(conn, service_request_path(conn, :show, patient_id, episode_id, id))
      assert json_response(conn, 404)
    end

    test "success get service_request", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      episode_id = UUID.uuid4()
      episode = build(:episode, id: episode_id)

      encounter =
        build(:encounter,
          episode: reference_coding(Mongo.string_to_uuid(episode_id), system: "eHealth/resources", code: "episode")
        )

      encounter_id = encounter.id

      insert(:patient,
        _id: patient_id_hash,
        episodes: %{episode_id => episode},
        encounters: %{to_string(encounter_id) => encounter}
      )

      service_request =
        insert(:service_request, context: reference_coding(encounter_id, system: "eHealth/resources", code: "encounter"))

      id = to_string(service_request._id)

      conn = get(conn, service_request_path(conn, :show, patient_id, episode_id, id))
      assert response = json_response(conn, 200)
      assert %{"data" => %{"id" => ^id}} = response
    end
  end

  describe "search service requests" do
    test "requisition is not present", %{conn: conn} do
      conn = get(conn, service_request_path(conn, :search))

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.requisition",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "required property requisition was not present",
                       "params" => [],
                       "rule" => "required"
                     }
                   ]
                 }
               ]
             } = json_response(conn, 422)["error"]
    end

    test "additional params were sent", %{conn: conn} do
      search_params = %{
        "code" => UUID.uuid4(),
        "patient_id" => UUID.uuid4(),
        "episode_id" => UUID.uuid4(),
        "requisition" => "requisition",
        "status" => "active",
        "requester_legal_entity" => UUID.uuid4(),
        "used_by_legal_entity" => UUID.uuid4()
      }

      resp =
        conn
        |> get(service_request_path(conn, :search), search_params)
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.code",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.episode_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.patient_id",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.patient_id_hash",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.requester_legal_entity",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               },
               %{
                 "entry" => "$.used_by_legal_entity",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               }
             ] = resp["error"]["invalid"]
    end

    test "success search", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      service_request1 = insert(:service_request)
      insert(:service_request, requisition: service_request1.requisition)
      insert(:service_request)
      requisition = Encryptor.decrypt(service_request1.requisition)
      conn = get(conn, service_request_path(conn, :search), %{requisition: requisition})
      response = json_response(conn, 200)
      assert 2 == response["paging"]["total_entries"]
      assert Enum.all?(response["data"], &(Map.get(&1, "requisition") == requisition))
    end

    test "status search", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      service_request1 = insert(:service_request)
      insert(:service_request, requisition: service_request1.requisition, status: ServiceRequest.status(:completed))
      insert(:service_request)
      requisition = Encryptor.decrypt(service_request1.requisition)

      conn =
        get(conn, service_request_path(conn, :search), %{
          requisition: requisition,
          status: service_request1.status
        })

      response = json_response(conn, 200)
      assert 1 == response["paging"]["total_entries"]
      assert Enum.all?(response["data"], &(Map.get(&1, "requisition") == requisition))
      assert Enum.all?(response["data"], &(Map.get(&1, "status") == service_request1.status))
    end

    test "pagination search", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      service_request1 = insert(:service_request)
      insert(:service_request, requisition: service_request1.requisition)
      insert(:service_request, requisition: service_request1.requisition)
      requisition = Encryptor.decrypt(service_request1.requisition)

      conn =
        get(conn, service_request_path(conn, :search), %{
          requisition: requisition,
          page: 2,
          page_size: 2
        })

      response = json_response(conn, 200)
      assert 3 == response["paging"]["total_entries"]
      assert 2 == response["paging"]["page_number"]
    end
  end

  describe "search service requests in patient context" do
    test "patient not found", %{conn: conn} do
      conn = get(conn, service_request_path(conn, :patient_context_search, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = get(conn, service_request_path(conn, :patient_context_search, patient_id))
      assert json_response(conn, 409)
    end

    test "additional params were sent", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      episode_id = UUID.uuid4()
      episode = build(:episode, id: episode_id)

      encounter =
        build(:encounter,
          episode: reference_coding(Mongo.string_to_uuid(episode_id), system: "eHealth/resources", code: "episode")
        )

      encounter_id = encounter.id

      insert(:patient,
        _id: patient_id_hash,
        episodes: %{episode_id => episode},
        encounters: %{to_string(encounter_id) => encounter}
      )

      search_params = %{
        "code" => UUID.uuid4(),
        "episode_id" => UUID.uuid4(),
        "requisition" => "requisition",
        "status" => "active",
        "requester_legal_entity" => UUID.uuid4(),
        "used_by_legal_entity" => UUID.uuid4()
      }

      resp =
        conn
        |> get(service_request_path(conn, :patient_context_search, patient_id, search_params))
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.requisition",
                 "entry_type" => "json_data_property",
                 "rules" => [%{"description" => "schema does not allow additional properties", "rule" => "schema"}]
               }
             ] = resp["error"]["invalid"]
    end

    test "success search by episode_id", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      episode_id = UUID.uuid4()
      episode = build(:episode, id: episode_id)

      encounter =
        build(:encounter,
          episode: reference_coding(Mongo.string_to_uuid(episode_id), system: "eHealth/resources", code: "episode")
        )

      encounter_id = encounter.id

      insert(:patient,
        _id: patient_id_hash,
        episodes: %{episode_id => episode},
        encounters: %{to_string(encounter_id) => encounter}
      )

      service_request =
        insert(:service_request,
          context: reference_coding(encounter_id, system: "eHealth/resources", code: "encounter"),
          subject: patient_id_hash
        )

      insert(:service_request, subject: patient_id_hash)
      id = to_string(service_request._id)
      conn = get(conn, service_request_path(conn, :patient_context_search, patient_id), %{"episode_id" => episode_id})

      assert response = json_response(conn, 200)
      assert [%{"id" => ^id}] = response["data"]
    end

    test "success search by status", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      service_request = insert(:service_request, subject: patient_id_hash, status: ServiceRequest.status(:completed))

      insert(:service_request, subject: patient_id_hash)
      id = to_string(service_request._id)

      conn =
        get(conn, service_request_path(conn, :patient_context_search, patient_id), %{
          "status" => ServiceRequest.status(:completed)
        })

      assert response = json_response(conn, 200)
      assert [%{"id" => ^id}] = response["data"]
    end

    test "success search by requester_legal_entity", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      requester_legal_entity_id = UUID.uuid4()

      service_request =
        insert(:service_request,
          subject: patient_id_hash,
          requester_legal_entity:
            reference_coding(Mongo.string_to_uuid(requester_legal_entity_id),
              system: "eHealth/resources",
              code: "legal_entity"
            )
        )

      insert(:service_request, subject: patient_id_hash)
      id = to_string(service_request._id)

      conn =
        get(conn, service_request_path(conn, :patient_context_search, patient_id), %{
          "requester_legal_entity" => requester_legal_entity_id
        })

      assert response = json_response(conn, 200)
      assert [%{"id" => ^id}] = response["data"]
    end

    test "success search by used_by_legal_entity", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      used_by_legal_entity_id = UUID.uuid4()

      service_request =
        insert(:service_request,
          subject: patient_id_hash,
          used_by_legal_entity:
            reference_coding(Mongo.string_to_uuid(used_by_legal_entity_id),
              system: "eHealth/resources",
              code: "legal_entity"
            )
        )

      insert(:service_request, subject: patient_id_hash)
      id = to_string(service_request._id)

      conn =
        get(conn, service_request_path(conn, :patient_context_search, patient_id), %{
          "used_by_legal_entity" => used_by_legal_entity_id
        })

      assert response = json_response(conn, 200)
      assert [%{"id" => ^id}] = response["data"]
    end

    test "success search by code", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      code = UUID.uuid4()

      service_request =
        insert(:service_request,
          subject: patient_id_hash,
          code:
            reference_coding(Mongo.string_to_uuid(code),
              system: "eHealth/resources",
              code: "service"
            )
        )

      insert(:service_request, subject: patient_id_hash)
      id = to_string(service_request._id)

      conn =
        get(conn, service_request_path(conn, :patient_context_search, patient_id), %{
          "code" => code
        })

      assert response = json_response(conn, 200)
      assert [%{"id" => ^id}] = response["data"]
    end
  end

  describe "create service request" do
    test "patient not found", %{conn: conn} do
      conn = post(conn, service_request_path(conn, :create, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = post(conn, service_request_path(conn, :create, patient_id))
      assert json_response(conn, 409)
    end

    test "no signed data set", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn = post(conn, service_request_path(conn, :create, patient_id))
      assert response = json_response(conn, 422)

      assert [
               %{
                 "entry" => "$.signed_data",
                 "entry_type" => "json_data_property",
                 "rules" => [
                   %{
                     "description" => "required property signed_data was not present",
                     "params" => [],
                     "rule" => "required"
                   }
                 ]
               }
             ] = response["error"]["invalid"]
    end

    test "success create service request", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [%{"collection" => "jobs", "operation" => "insert"}]
               } = Jason.decode!(args)

        :ok
      end)

      assert conn
             |> post(service_request_path(conn, :create, patient_id), %{
               "signed_data" => Base.encode64(Jason.encode!(%{}))
             })
             |> json_response(202)
             |> Map.get("data")
             |> assert_json_schema("jobs/job_details_pending.json")
    end
  end

  describe "use service request" do
    test "used_by_legal_entity is not set", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      conn = patch(conn, service_request_path(conn, :use, UUID.uuid4()))
      assert response = json_response(conn, 422)

      assert [
               %{
                 "entry" => "$.used_by_legal_entity",
                 "entry_type" => "json_data_property",
                 "rules" => [
                   %{
                     "description" => "required property used_by_legal_entity was not present",
                     "params" => [],
                     "rule" => "required"
                   }
                 ]
               }
             ] = response["error"]["invalid"]
    end

    test "success use service request", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [%{"collection" => "jobs", "operation" => "insert"}]
               } = Jason.decode!(args)

        :ok
      end)

      assert conn
             |> patch(service_request_path(conn, :use, UUID.binary_to_string!(id)), %{
               "used_by_employee" => %{"identifier" => %{"value" => ""}},
               "used_by_legal_entity" => %{"identifier" => %{"value" => ""}}
             })
             |> json_response(202)
             |> Map.get("data")
             |> assert_json_schema("jobs/job_details_pending.json")
    end
  end

  describe "release service request" do
    test "success release service request", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [%{"collection" => "jobs", "operation" => "insert"}]
               } = Jason.decode!(args)

        :ok
      end)

      assert conn
             |> patch(service_request_path(conn, :release, UUID.binary_to_string!(id)))
             |> json_response(202)
             |> Map.get("data")
             |> assert_json_schema("jobs/job_details_pending.json")
    end
  end

  describe "recall service request" do
    test "patient not found", %{conn: conn} do
      conn = patch(conn, service_request_path(conn, :recall, UUID.uuid4(), UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = patch(conn, service_request_path(conn, :recall, patient_id, UUID.uuid4()))
      assert json_response(conn, 409)
    end

    test "invalid params", %{conn: conn} do
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      conn = patch(conn, service_request_path(conn, :recall, patient_id, UUID.uuid4()), %{})
      json_response(conn, 422)
    end

    test "success recall service request", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [%{"collection" => "jobs", "operation" => "insert"}]
               } = Jason.decode!(args)

        :ok
      end)

      assert conn
             |> patch(service_request_path(conn, :recall, patient_id, UUID.binary_to_string!(id)), %{
               "signed_data" => Jason.encode!(%{})
             })
             |> json_response(202)
             |> Map.get("data")
             |> assert_json_schema("jobs/job_details_pending.json")
    end
  end

  describe "cancel service request" do
    test "patient not found", %{conn: conn} do
      conn = patch(conn, service_request_path(conn, :cancel, UUID.uuid4(), UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = patch(conn, service_request_path(conn, :cancel, patient_id, UUID.uuid4()))
      assert json_response(conn, 409)
    end

    test "invalid params", %{conn: conn} do
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      insert(:patient, _id: patient_id_hash)

      conn = patch(conn, service_request_path(conn, :cancel, patient_id, UUID.uuid4()), %{})
      json_response(conn, 422)
    end

    test "success cancel service request", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [%{"collection" => "jobs", "operation" => "insert"}]
               } = Jason.decode!(args)

        :ok
      end)

      assert conn
             |> patch(service_request_path(conn, :cancel, patient_id, UUID.binary_to_string!(id)), %{
               "signed_data" => Jason.encode!(%{})
             })
             |> json_response(202)
             |> Map.get("data")
             |> assert_json_schema("jobs/job_details_pending.json")
    end
  end

  describe "process service request" do
    test "success process service request", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [%{"collection" => "jobs", "operation" => "insert"}]
               } = Jason.decode!(args)

        :ok
      end)

      assert conn
             |> patch(service_request_path(conn, :process, UUID.binary_to_string!(id)))
             |> json_response(202)
             |> Map.get("data")
             |> assert_json_schema("jobs/job_details_pending.json")
    end
  end

  describe "complete service request" do
    test "completed_with is not set", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      conn = patch(conn, service_request_path(conn, :complete, UUID.uuid4()))
      assert response = json_response(conn, 422)

      assert [
               %{
                 "entry" => "$.completed_with",
                 "entry_type" => "json_data_property",
                 "rules" => [
                   %{
                     "description" => "required property completed_with was not present",
                     "params" => [],
                     "rule" => "required"
                   }
                 ]
               }
             ] = response["error"]["invalid"]
    end

    test "success complete service request", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      service_request = insert(:service_request)
      %BSON.Binary{binary: id} = service_request._id

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [%{"collection" => "jobs", "operation" => "insert"}]
               } = Jason.decode!(args)

        :ok
      end)

      assert conn
             |> patch(service_request_path(conn, :complete, UUID.binary_to_string!(id)), %{
               "completed_with" => %{"identifier" => %{"value" => ""}}
             })
             |> json_response(202)
             |> Map.get("data")
             |> assert_json_schema("jobs/job_details_pending.json")
    end
  end
end
