defmodule Api.Web.EncounterControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase

  import Core.Expectations.CasherExpectation
  import Core.TestViews.CancelEncounterPackageView
  import Mox

  alias Core.Patient
  alias Core.Patients

  @status_error "entered_in_error"

  describe "create visit" do
    test "patient not found", %{conn: conn} do
      conn = post(conn, encounter_path(conn, :create, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = post(conn, encounter_path(conn, :create, patient_id))
      assert json_response(conn, 409)
    end

    test "no signed data set", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn = post(conn, encounter_path(conn, :create, patient_id))
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

    test "success create visit", %{conn: conn} do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      stub(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      now = DateTime.utc_now()

      conn =
        post(conn, encounter_path(conn, :create, patient_id), %{
          "visit" => %{
            "id" => UUID.uuid4(),
            "period" => %{"start" => DateTime.to_iso8601(now), "end" => DateTime.to_iso8601(now)}
          },
          "signed_data" => Base.encode64(Jason.encode!(%{}))
        })

      assert response = json_response(conn, 202)

      assert %{
               "data" => %{
                 "id" => _,
                 "inserted_at" => _,
                 "status" => "pending",
                 "updated_at" => _
               }
             } = response
    end
  end

  describe "show encounter" do
    test "successful show", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      encounter_in = build(:encounter)
      encounter_out = build(:encounter)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{
          UUID.binary_to_string!(encounter_in.id.binary) => encounter_in,
          UUID.binary_to_string!(encounter_out.id.binary) => encounter_out
        }
      )

      expect_get_person_data(patient_id)

      assert conn
             |> get(encounter_path(conn, :show, patient_id, UUID.binary_to_string!(encounter_in.id.binary)))
             |> json_response(200)
             |> Map.get("data")
             |> assert_json_schema("encounters/encounter_show.json")
    end

    test "invalid patient uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect_get_person_data_empty()

      conn
      |> get(encounter_path(conn, :show, UUID.uuid4(), UUID.uuid4()))
      |> json_response(403)
    end

    test "invalid encounter uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      encounter = build(:encounter)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter})
      expect_get_person_data(patient_id)

      conn
      |> get(encounter_path(conn, :show, patient_id, UUID.uuid4()))
      |> json_response(404)
    end

    test "get patient when no encounters", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, encounters: %{})
      expect_get_person_data(patient_id)

      conn
      |> get(encounter_path(conn, :show, patient_id, UUID.uuid4()))
      |> json_response(404)
    end

    test "success show encounter in episode context", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      encounter_in = build(:encounter)
      encounter_out = build(:encounter)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        encounters: %{
          to_string(encounter_in.id) => encounter_in,
          to_string(encounter_out.id) => encounter_out
        }
      )

      expect_get_person_data(patient_id)

      assert conn
             |> get(
               episode_context_encounter_path(
                 conn,
                 :show,
                 patient_id,
                 to_string(encounter_in.episode.identifier.value),
                 to_string(encounter_in.id)
               )
             )
             |> json_response(200)
             |> Map.get("data")
             |> assert_json_schema("encounters/encounter_show.json")
    end
  end

  describe "index encounter" do
    test "successful search", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(encounter_path(conn, :index, patient_id))
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "encounters/encounter_show.json"))
      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "successful search in episode context", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      encounter1 = build(:encounter)
      encounter2 = build(:encounter)

      insert(:patient,
        _id: patient_id_hash,
        encounters: %{
          to_string(encounter1.id) => encounter1,
          to_string(encounter2.id) => encounter2
        }
      )

      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(episode_context_encounter_path(conn, :index, patient_id, to_string(encounter1.episode.identifier.value)))
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "encounters/encounter_show.json"))
      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]
    end

    test "successful search with search parameters", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      episode = build(:reference)
      date_from = Date.utc_today() |> Date.add(-20) |> Date.to_iso8601()
      date_to = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

      encounter_in = build(:encounter, date: get_datetime(-15), episode: episode)
      encounter_out_1 = build(:encounter, date: get_datetime(-15))
      encounter_out_2 = build(:encounter, date: get_datetime())

      encounters =
        [encounter_in, encounter_out_1, encounter_out_2]
        |> Enum.into(%{}, fn %{id: %BSON.Binary{binary: id}} = encounter ->
          {UUID.binary_to_string!(id), encounter}
        end)

      insert(:patient, _id: patient_id_hash, encounters: encounters)
      expect_get_person_data(patient_id)

      search_params = %{
        "episode_id" => UUID.binary_to_string!(episode.identifier.value.binary),
        "date_from" => date_from,
        "date_to" => date_to
      }

      resp =
        conn
        |> get(encounter_path(conn, :index, patient_id), search_params)
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "encounters/encounter_show.json"))
      assert %{"page_number" => 1, "total_entries" => 1, "total_pages" => 1} = resp["paging"]

      encounter = hd(resp["data"])
      assert encounter["id"] == UUID.binary_to_string!(encounter_in.id.binary)
      refute encounter["id"] == UUID.binary_to_string!(encounter_out_1.id.binary)
      refute encounter["id"] == UUID.binary_to_string!(encounter_out_2.id.binary)

      {:ok, datetime, _} = DateTime.from_iso8601(encounter["date"])
      assert Date.compare(Date.from_iso8601!(date_from), DateTime.to_date(datetime)) in [:lt, :eq]

      assert Date.compare(Date.from_iso8601!(date_to), DateTime.to_date(datetime)) in [:gt, :eq]

      assert get_in(encounter, ~w(episode identifier value)) == UUID.binary_to_string!(episode.identifier.value.binary)
    end

    test "invalid patient uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect_get_person_data_empty()

      conn
      |> get(encounter_path(conn, :index, UUID.uuid4()))
      |> json_response(403)
    end

    test "get patient when no encounters", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, encounters: %{})
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(encounter_path(conn, :index, patient_id))
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "encounters/encounter_show.json"))
      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end

    test "get patient when encounters list is null", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash, encounters: nil)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(encounter_path(conn, :index, patient_id))
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "encounters/encounter_show.json"))
      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end
  end

  describe "cancel encounter" do
    setup %{conn: conn} do
      {:ok, conn: put_consumer_id_header(conn)}
    end

    test "success", %{conn: conn} do
      episode = build(:episode)
      encounter = build(:encounter, episode: reference_coding(episode.id, code: "episode"))
      context = reference_coding(encounter.id, code: "encounter")

      expect(KafkaMock, :publish_mongo_event, 3, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      immunization = build(:immunization, context: context, status: @status_error)
      allergy_intolerance = build(:allergy_intolerance, context: context)
      allergy_intolerance2 = build(:allergy_intolerance)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        episodes: %{UUID.binary_to_string!(episode.id.binary) => episode},
        encounters: %{UUID.binary_to_string!(encounter.id.binary) => encounter},
        immunizations: %{UUID.binary_to_string!(immunization.id.binary) => immunization},
        allergy_intolerances: %{
          UUID.binary_to_string!(allergy_intolerance.id.binary) => allergy_intolerance,
          UUID.binary_to_string!(allergy_intolerance2.id.binary) => allergy_intolerance2
        }
      )

      condition =
        insert(
          :condition,
          patient_id: patient_id_hash,
          context: context,
          verification_status: @status_error
        )

      observation = insert(:observation, patient_id: patient_id_hash, context: context)

      request_data = %{
        "signed_data" =>
          %{
            "encounter" => render(:encounter, encounter),
            "conditions" => render(:conditions, [condition]),
            "observations" => render(:observations, [observation]),
            "immunizations" => render(:immunizations, [immunization]),
            "allergy_intolerances" => render(:allergy_intolerances, [allergy_intolerance])
          }
          |> Jason.encode!()
          |> Base.encode64()
      }

      expect_get_person_data(patient_id)

      assert conn
             |> patch(encounter_path(conn, :cancel, patient_id), request_data)
             |> json_response(202)
             |> get_in(["data", "status"])
             |> Kernel.==("pending")
    end

    test "fail on invalid signed content", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      assert conn
             |> patch(encounter_path(conn, :cancel, patient_id), %{"invalid_signed_data" => 1})
             |> json_response(422)
             |> get_in(["error", "message"])
             |> String.contains?("Validation failed.")
    end
  end

  defp get_datetime(day_shift \\ 0) do
    date = Date.utc_today() |> Date.add(day_shift) |> Date.to_erl()
    {date, {0, 0, 0}} |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
  end
end
