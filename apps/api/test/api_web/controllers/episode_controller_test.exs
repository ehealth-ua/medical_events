defmodule Api.Web.EpisodeControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase

  import Core.Expectations.CasherExpectation
  import Mox

  alias Core.Episode
  alias Core.Patient
  alias Core.Patients

  setup %{conn: conn} do
    {:ok, conn: put_consumer_id_header(conn)}
  end

  describe "create episode" do
    test "patient not found", %{conn: conn} do
      conn = post(conn, episode_path(conn, :create, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = post(conn, episode_path(conn, :create, patient_id))
      assert json_response(conn, 409)
    end

    test "json schema validation failed", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn = post(conn, episode_path(conn, :create, patient_id), %{})
      assert json_response(conn, 422)
    end

    test "success create episode", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      data = %{
        "id" => UUID.uuid4(),
        "name" => "ОРВИ 2018",
        "status" => Episode.status(:active),
        "type" => "primary_care",
        "managing_organization" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"system" => "eHealth/resources", "code" => "legal_entity"}]},
            "value" => UUID.uuid4()
          }
        },
        "period" => %{"start" => to_string(Date.utc_today())},
        "care_manager" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"system" => "eHealth/resources", "code" => "employee"}]},
            "value" => UUID.uuid4()
          }
        }
      }

      conn1 = post(conn, episode_path(conn, :create, patient_id), data)

      assert %{
               "data" => %{
                 "id" => job_id,
                 "status" => "pending"
               }
             } = json_response(conn1, 202)

      conn2 = post(conn, episode_path(conn, :create, patient_id), data)

      href = "/jobs/#{job_id}"

      assert %{
               "data" => %{
                 "eta" => _,
                 "links" => [%{"entity" => "job", "href" => ^href}],
                 "status" => "pending",
                 "status_code" => 202
               }
             } = json_response(conn2, 200)
    end
  end

  describe "update episode" do
    test "patient not found", %{conn: conn} do
      conn = patch(conn, episode_path(conn, :update, UUID.uuid4(), UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "episode not found", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn = patch(conn, episode_path(conn, :update, patient_id, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = patch(conn, episode_path(conn, :update, patient_id, UUID.uuid4()))
      assert json_response(conn, 409)
    end

    test "json schema validation failed", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      conn = patch(conn, episode_path(conn, :update, patient_id, episode_id), %{})
      assert json_response(conn, 422)
    end

    test "success update episode", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, 2, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      data = %{
        "name" => "ОРВИ 2019",
        "managing_organization" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"system" => "eHealth/resources", "code" => "legal_entity"}]},
            "value" => UUID.uuid4()
          }
        },
        "care_manager" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"system" => "eHealth/resources", "code" => "employee"}]},
            "value" => UUID.uuid4()
          }
        }
      }

      conn1 = patch(conn, episode_path(conn, :update, patient_id, episode_id), data)

      assert %{
               "data" => %{
                 "id" => job_id,
                 "status" => "pending"
               }
             } = json_response(conn1, 202)

      conn2 = patch(conn, episode_path(conn, :update, patient_id, episode_id), data)

      href = "/jobs/#{job_id}"

      assert %{
               "data" => %{
                 "eta" => _,
                 "links" => [%{"entity" => "job", "href" => ^href}],
                 "status" => "pending",
                 "status_code" => 202
               }
             } = json_response(conn2, 200)
    end
  end

  describe "close episode" do
    test "patient not found", %{conn: conn} do
      conn = patch(conn, episode_path(conn, :close, UUID.uuid4(), UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "episode not found", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn = patch(conn, episode_path(conn, :close, patient_id, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = patch(conn, episode_path(conn, :close, patient_id, UUID.uuid4()))
      assert json_response(conn, 409)
    end

    test "json schema validation failed", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      conn = patch(conn, episode_path(conn, :close, patient_id, episode_id), %{})
      assert json_response(conn, 422)
    end

    test "success close episode", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, 2, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      data = %{
        "period" => %{
          "end" => to_string(Date.utc_today())
        },
        "status_reason" => %{"coding" => [%{"system" => "eHealth/episode_closing_reasons", "code" => "legal_entity"}]}
      }

      conn1 = patch(conn, episode_path(conn, :close, patient_id, episode_id), data)

      assert %{
               "data" => %{
                 "id" => job_id,
                 "status" => "pending"
               }
             } = json_response(conn1, 202)

      conn2 = patch(conn, episode_path(conn, :close, patient_id, episode_id), data)

      href = "/jobs/#{job_id}"

      assert %{
               "data" => %{
                 "eta" => _,
                 "links" => [%{"entity" => "job", "href" => ^href}],
                 "status" => "pending",
                 "status_code" => 202
               }
             } = json_response(conn2, 200)
    end
  end

  describe "cancel episode" do
    test "patient not found", %{conn: conn} do
      conn = patch(conn, episode_path(conn, :cancel, UUID.uuid4(), UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "episode not found", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      conn = patch(conn, episode_path(conn, :cancel, patient_id, UUID.uuid4()))
      assert json_response(conn, 404)
    end

    test "patient is not active", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, status: Patient.status(:inactive), _id: patient_id_hash)

      conn = patch(conn, episode_path(conn, :cancel, patient_id, UUID.uuid4()))
      assert json_response(conn, 409)
    end

    test "json schema validation failed", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      conn = patch(conn, episode_path(conn, :cancel, patient_id, episode_id), %{})
      assert json_response(conn, 422)
    end

    test "success cancel episode", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect(KafkaMock, :publish_medical_event, 2, fn _ -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      patient = insert(:patient, _id: patient_id_hash)
      episode_id = patient.episodes |> Map.keys() |> hd

      data = %{
        "status_reason" => %{
          "coding" => [%{"system" => "eHealth/cancellation_reasons", "code" => "misspelling"}]
        },
        "explanatory_letter" => "Епізод був відмінений у зв'язку з помилкою при виборі пацієнта"
      }

      conn1 = patch(conn, episode_path(conn, :cancel, patient_id, episode_id), data)

      assert %{
               "data" => %{
                 "id" => job_id,
                 "status" => "pending"
               }
             } = json_response(conn1, 202)

      conn2 = patch(conn, episode_path(conn, :cancel, patient_id, episode_id), data)

      href = "/jobs/#{job_id}"

      assert %{
               "data" => %{
                 "eta" => _,
                 "links" => [%{"entity" => "job", "href" => ^href}],
                 "status" => "pending",
                 "status_code" => 202
               }
             } = json_response(conn2, 200)
    end
  end

  describe "show episode" do
    test "get episode success", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      episode = build(:episode)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode}, _id: patient_id_hash)

      expect_get_person_data(patient_id)

      conn
      |> get(episode_path(conn, :show, patient_id, UUID.binary_to_string!(episode.id.binary)))
      |> json_response(200)
      |> Map.get("data")
      |> assert_json_schema("episodes/episode_show.json")
    end

    test "get episode invalid patient uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      expect_get_person_data_empty()

      conn
      |> get(episode_path(conn, :show, "invalid-uuid", UUID.uuid4()))
      |> json_response(401)
    end

    test "get episode invalid episode uuid", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      episode = build(:episode)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: %{UUID.binary_to_string!(episode.id.binary) => episode}, _id: patient_id_hash)

      expect_get_person_data(patient_id)

      conn
      |> get(episode_path(conn, :show, patient_id, "invalid-episode-uuid"))
      |> json_response(404)
    end

    test "get episode when no episodes", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: %{}, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      conn
      |> get(episode_path(conn, :show, patient_id, UUID.uuid4()))
      |> json_response(404)
    end
  end

  describe "list episodes" do
    test "get episodes success", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(episode_path(conn, :index, patient_id))
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "episodes/episode_show.json"))
      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 1} = resp["paging"]
    end

    test "get episodes no episodes", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: %{}, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(episode_path(conn, :index, patient_id))
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "episodes/episode_show.json"))
      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end

    test "get episodes is nil", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: nil, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(episode_path(conn, :index, patient_id))
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "episodes/episode_show.json"))
      assert %{"page_number" => 1, "total_entries" => 0, "total_pages" => 0} = resp["paging"]
    end

    test "get episodes order by inserted first episode", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      tomorrow = DateTime.from_unix!(DateTime.to_unix(DateTime.utc_now()) + 60 * 60 * 24)
      yesterday = DateTime.from_unix!(DateTime.to_unix(DateTime.utc_now()) - 60 * 60 * 24)

      episode_t = build(:episode, inserted_at: tomorrow)
      episode_y = build(:episode, inserted_at: yesterday)

      episodes =
        1..200
        |> Enum.reduce(%{}, fn _, acc ->
          episode = build(:episode)
          Map.put(acc, UUID.binary_to_string!(episode.id.binary), episode)
        end)
        |> Map.put(UUID.binary_to_string!(episode_t.id.binary), episode_t)
        |> Map.put(UUID.binary_to_string!(episode_y.id.binary), episode_y)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: episodes, _id: patient_id_hash)

      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(episode_path(conn, :index, patient_id), %{"page_size" => "1"})
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "episodes/episode_show.json"))
      assert [%{"id" => idt} | _] = resp["data"]
      assert idt == UUID.binary_to_string!(episode_t.id.binary)
      assert %{"page_number" => 1, "total_entries" => 202, "total_pages" => 202, "page_size" => 1} = resp["paging"]
    end

    test "get episodes order by inserted last episode", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      tomorrow = DateTime.from_unix!(DateTime.to_unix(DateTime.utc_now()) + 60 * 60 * 24)
      yesterday = DateTime.from_unix!(DateTime.to_unix(DateTime.utc_now()) - 60 * 60 * 24)

      episode_t = build(:episode, inserted_at: tomorrow)
      episode_y = build(:episode, inserted_at: yesterday)

      episodes =
        1..200
        |> Enum.reduce(%{}, fn _, acc ->
          episode = build(:episode)
          Map.put(acc, UUID.binary_to_string!(episode.id.binary), episode)
        end)
        |> Map.put(UUID.binary_to_string!(episode_t.id.binary), episode_t)
        |> Map.put(UUID.binary_to_string!(episode_y.id.binary), episode_y)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: episodes, _id: patient_id_hash)

      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(episode_path(conn, :index, patient_id), %{"page_size" => "200", "page" => "2"})
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "episodes/episode_show.json"))
      assert [_, %{"id" => idy}] = resp["data"]
      assert idy == UUID.binary_to_string!(episode_y.id.binary)
      assert %{"page_number" => 2, "total_entries" => 202, "total_pages" => 2, "page_size" => 200} = resp["paging"]
    end

    test "get episodes paging string instead of int", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)
      expect_get_person_data(patient_id)

      resp =
        conn
        |> get(episode_path(conn, :index, patient_id), %{"page_size" => "1"})
        |> json_response(200)

      Enum.each(resp["data"], &assert_json_schema(&1, "episodes/episode_show.json"))
      assert %{"page_number" => 1, "total_entries" => 2, "total_pages" => 2, "page_size" => 1} = resp["paging"]
    end
  end

  describe "list episodes by period" do
    setup %{conn: conn} do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      week_ago = Date.utc_today() |> Date.add(-7) |> Date.to_string()
      next_week = Date.utc_today() |> Date.add(7) |> Date.to_string()
      tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_string()
      yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_string()
      today = Date.to_string(Date.utc_today())

      tomorrow_inactive_episode = build(:episode, period: build(:period, start: tomorrow, end: tomorrow))
      tomorrow_active_episode = build(:episode, period: build(:period, start: tomorrow, end: next_week))

      today_inactive_episode = build(:episode, period: build(:period, start: today, end: tomorrow))
      today_active_episode = build(:episode, period: build(:period, start: today, end: next_week))

      week_ago_inactive_episode = build(:episode, period: build(:period, start: week_ago, end: yesterday))
      week_ago_today_episode = build(:episode, period: build(:period, start: week_ago, end: today))
      week_ago_next_week_episode = build(:episode, period: build(:period, start: week_ago, end: next_week))

      week_ago_noend_episode = build(:episode, period: build(:period, start: week_ago, end: nil))
      today_noend_episode = build(:episode, period: build(:period, start: today, end: nil))
      tomorrow_noend_episode = build(:episode, period: build(:period, start: tomorrow, end: nil))
      next_week_noend_episode = build(:episode, period: build(:period, start: next_week, end: nil))

      builded_episodes = [
        tomorrow_inactive_episode,
        tomorrow_active_episode,
        today_inactive_episode,
        today_active_episode,
        week_ago_inactive_episode,
        week_ago_today_episode,
        week_ago_next_week_episode,
        week_ago_noend_episode,
        today_noend_episode,
        tomorrow_noend_episode,
        next_week_noend_episode
      ]

      episodes =
        Enum.reduce(builded_episodes, %{}, fn episode, episodes ->
          Map.put(episodes, UUID.binary_to_string!(episode.id.binary), episode)
        end)

      episode_id = fn episode ->
        UUID.binary_to_string!(episode.id.binary)
      end

      episodes_state = %{
        tomorrow_inactive_episode: episode_id.(tomorrow_inactive_episode),
        tomorrow_active_episode: episode_id.(tomorrow_active_episode),
        today_inactive_episode: episode_id.(today_inactive_episode),
        today_active_episode: episode_id.(today_active_episode),
        week_ago_inactive_episode: episode_id.(week_ago_inactive_episode),
        week_ago_today_episode: episode_id.(week_ago_today_episode),
        week_ago_next_week_episode: episode_id.(week_ago_next_week_episode),
        week_ago_noend_episode: episode_id.(week_ago_noend_episode),
        today_noend_episode: episode_id.(today_noend_episode),
        tomorrow_noend_episode: episode_id.(tomorrow_noend_episode),
        next_week_noend_episode: episode_id.(next_week_noend_episode)
      }

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: episodes, _id: patient_id_hash)

      expect_get_person_data(patient_id)

      %{conn: conn}
      |> Map.put(:episodes, episodes_state)
      |> Map.put(:patient_id, patient_id)
      |> Map.put(:week_ago, week_ago)
      |> Map.put(:next_week, next_week)
      |> Map.put(:tomorrow, tomorrow)
      |> Map.put(:today, today)
      |> Map.put(:yesterday, yesterday)
    end

    test "get episodes by period_from", %{conn: conn, today: today, patient_id: patient_id, episodes: episodes} do
      %{
        today_inactive_episode: today_inactive_episode,
        today_active_episode: today_active_episode,
        week_ago_today_episode: week_ago_today_episode,
        week_ago_next_week_episode: week_ago_next_week_episode,
        week_ago_noend_episode: week_ago_noend_episode,
        today_noend_episode: today_noend_episode,
        next_week_noend_episode: next_week_noend_episode,
        tomorrow_noend_episode: tomorrow_noend_episode,
        tomorrow_inactive_episode: tomorrow_inactive_episode,
        tomorrow_active_episode: tomorrow_active_episode
      } = episodes

      resp =
        conn
        |> get(episode_path(conn, :index, patient_id), %{"period_from" => today})
        |> json_response(200)

      ids =
        Enum.reduce(resp["data"], [], fn episode, ids ->
          assert_json_schema(episode, "episodes/episode_show.json")
          [episode["id"] | ids]
        end)

      asserd_matching_ids(ids, [
        today_inactive_episode,
        today_active_episode,
        week_ago_today_episode,
        week_ago_next_week_episode,
        week_ago_noend_episode,
        today_noend_episode,
        next_week_noend_episode,
        tomorrow_noend_episode,
        tomorrow_inactive_episode,
        tomorrow_active_episode
      ])
    end

    test "get episodes by period_to", %{conn: conn, patient_id: patient_id, episodes: episodes, yesterday: yesterday} do
      %{
        week_ago_inactive_episode: week_ago_inactive_episode,
        week_ago_today_episode: week_ago_today_episode,
        week_ago_next_week_episode: week_ago_next_week_episode,
        week_ago_noend_episode: week_ago_noend_episode
      } = episodes

      resp =
        conn
        |> get(episode_path(conn, :index, patient_id), %{"period_to" => yesterday})
        |> json_response(200)

      ids =
        Enum.reduce(resp["data"], [], fn episode, ids ->
          assert_json_schema(episode, "episodes/episode_show.json")
          [episode["id"] | ids]
        end)

      asserd_matching_ids(ids, [
        week_ago_inactive_episode,
        week_ago_today_episode,
        week_ago_next_week_episode,
        week_ago_noend_episode
      ])
    end

    test "get episodes by period_from, period_to", %{
      conn: conn,
      yesterday: yesterday,
      today: today,
      patient_id: patient_id,
      episodes: episodes
    } do
      %{
        today_inactive_episode: today_inactive_episode,
        today_active_episode: today_active_episode,
        week_ago_inactive_episode: week_ago_inactive_episode,
        week_ago_today_episode: week_ago_today_episode,
        week_ago_next_week_episode: week_ago_next_week_episode,
        week_ago_noend_episode: week_ago_noend_episode,
        today_noend_episode: today_noend_episode
      } = episodes

      resp =
        conn
        |> get(episode_path(conn, :index, patient_id), %{
          "period_from" => yesterday,
          "period_to" => today
        })
        |> json_response(200)

      ids =
        Enum.reduce(resp["data"], [], fn episode, ids ->
          assert_json_schema(episode, "episodes/episode_show.json")
          [episode["id"] | ids]
        end)

      asserd_matching_ids(ids, [
        today_inactive_episode,
        today_active_episode,
        week_ago_inactive_episode,
        week_ago_today_episode,
        week_ago_next_week_episode,
        week_ago_noend_episode,
        today_noend_episode
      ])
    end
  end

  describe "params validation" do
    setup %{conn: conn} do
      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      %{conn: conn}
    end

    test "get episodes by invalid params", %{conn: conn} do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)
      patient_id = UUID.uuid4()
      expect_get_person_data(patient_id)
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, episodes: [], _id: patient_id_hash)

      resp =
        conn
        |> get(episode_path(conn, :index, patient_id), %{"period_from" => "invalid", "period_to" => "2017-01-01"})
        |> json_response(422)

      assert [
               %{
                 "rules" => [
                   %{
                     "description" => "expected \"invalid\" to be a valid ISO 8601 date",
                     "rule" => "date"
                   }
                 ]
               }
             ] = resp["error"]["invalid"]
    end
  end

  defp asserd_matching_ids(received_ids, db_ids) do
    assert MapSet.new(received_ids) == MapSet.new(db_ids)
  end
end
