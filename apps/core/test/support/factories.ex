defmodule Core.Factories do
  @moduledoc false

  use ExMachina

  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.Condition
  alias Core.Episode
  alias Core.Identifier
  alias Core.Job
  alias Core.Mongo
  alias Core.Observation
  alias Core.Observations.Value
  alias Core.Patient
  alias Core.Period
  alias Core.Reference
  # alias Core.StatusHistory
  alias Core.Visit

  def patient_factory do
    id = UUID.uuid4()
    visits = build_list(2, :visit)
    visits = Enum.into(visits, %{}, fn %{id: id} = visit -> {id, visit} end)

    episodes = build_list(2, :episode)
    episodes = Enum.into(episodes, %{}, fn %{id: id} = episode -> {id, episode} end)

    %Patient{
      _id: id,
      status: Patient.status(:active),
      visits: visits,
      episodes: episodes,
      encounters: %{},
      immunizations: %{},
      allergy_intolerances: %{},
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      inserted_by: id,
      updated_by: id
    }
  end

  def visit_factory do
    id = UUID.uuid4()

    %Visit{
      id: id,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      inserted_by: id,
      updated_by: id,
      period: build(:period)
    }
  end

  def period_factory do
    %Period{
      start: DateTime.utc_now(),
      end: DateTime.utc_now()
    }
  end

  def job_factory do
    %Job{
      _id: UUID.uuid4(),
      eta: NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
      status_code: 200,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      status: Job.status(:pending),
      response: ""
    }
  end

  def observation_factory do
    id = UUID.uuid4()
    now = DateTime.utc_now()

    %Observation{
      _id: UUID.uuid4(),
      status: Observation.status(:valid),
      categories: build_list(2, :codeable_concept),
      code: build(:codeable_concept),
      patient_id: UUID.uuid4(),
      context: build(:reference),
      effective_date_time: DateTime.utc_now(),
      issued: DateTime.utc_now(),
      primary_source: true,
      performer: build(:reference),
      interpretation: build(:codeable_concept),
      value: build(:value),
      body_site: build(:codeable_concept),
      inserted_at: now,
      updated_at: now,
      inserted_by: id,
      updated_by: id
    }
  end

  def episode_factory do
    id = UUID.uuid4()

    %Episode{
      id: UUID.uuid4(),
      status: Episode.status(:active),
      # status_history: build_list(1, :status_history),
      type: "primary_care",
      name: "ОРВИ 2018",
      managing_organization: build(:reference),
      period: build(:period),
      encounters: %{},
      care_manager: build(:reference),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      inserted_by: id,
      updated_by: id
    }
  end

  def value_factory do
    %Value{type: "string", value: "some value"}
  end

  def codeable_concept_factory do
    %CodeableConcept{
      coding: [build(:coding)],
      text: "code text"
    }
  end

  def coding_factory do
    %Coding{
      system: "local",
      code: "1"
    }
  end

  def reference_factory do
    %Reference{
      identifier: build(:identifier)
    }
  end

  def identifier_factory do
    %Identifier{
      type: build(:codeable_concept),
      value: UUID.uuid4()
    }
  end

  def condition_factory do
    patient_id = UUID.uuid4()

    %Condition{
      _id: UUID.uuid4(),
      patient_id: patient_id,
      inserted_by: patient_id,
      updated_by: patient_id,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  # def status_history_factory do
  #   %StatusHistory{
  #     status: Episode.status(:active),
  #     period: build(:period),
  #     inserted_at: NaiveDateTime.utc_now(),
  #     updated_at: NaiveDateTime.utc_now()
  #   }
  # end

  def insert(factory, args \\ [])

  def insert(:job, args) do
    :job
    |> build(args)
    |> Job.encode_response()
    |> insert_entity()
  end

  def insert(factory, args) do
    factory
    |> build(args)
    |> insert_entity()
  end

  defp insert_entity(entity) do
    {:ok, _} = Mongo.insert_one(entity)
    entity
  end
end
