defmodule Core.Factories do
  @moduledoc false

  use ExMachina

  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.Episode
  alias Core.Identifier
  alias Core.Job
  alias Core.Mongo
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
    id = UUID.uuid4()

    Job.encode_response(%Job{
      _id: id,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      status: Job.status(:pending),
      response: ""
    })
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
      care_manager: build(:reference),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      inserted_by: id,
      updated_by: id
    }
  end

  def codeable_concept_factory do
    %CodeableConcept{
      coding: build(:coding),
      text: "code text"
    }
  end

  def coding_factory do
    %Coding{
      system: "local",
      code: "1",
      display: "true"
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

  # def status_history_factory do
  #   %StatusHistory{
  #     status: Episode.status(:active),
  #     period: build(:period),
  #     inserted_at: NaiveDateTime.utc_now(),
  #     updated_at: NaiveDateTime.utc_now()
  #   }
  # end

  def insert(factory, args \\ []) do
    entity = build(factory, args)
    {:ok, _} = Mongo.insert_one(entity)
    entity
  end
end
