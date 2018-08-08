defmodule Core.Factories do
  @moduledoc false

  use ExMachina

  # alias Core.CodeableConcept
  # alias Core.Coding
  # alias Core.Episode
  alias Core.Patient
  alias Core.Period
  # alias Core.StatusHistory
  alias Core.Request
  alias Core.Visit

  def patient_factory do
    id = UUID.uuid4()
    visits = build_list(2, :visit)
    visits = Enum.into(visits, %{}, fn %{id: id} = visit -> {id, visit} end)

    %Patient{
      _id: id,
      status: Patient.status(:active),
      visits: visits,
      # episodes: build_list(2, :episode),
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

  def request_factory do
    id = UUID.uuid4()

    Request.encode_response(%Request{
      _id: id,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      status: Request.status(:pending),
      response: ""
    })
  end

  # def episode_factory do
  #   %Episode{
  #     status: Episode.status(:active),
  #     status_history: build_list(1, :status_history),
  #     type: build(:codeable_concept)
  #   }
  # end

  # def codeable_concept_factory do
  #   %CodeableConcept{
  #     coding: build(:coding),
  #     text: "code text"
  #   }
  # end

  # def coding_factory do
  #   %Coding{
  #     system: "local",
  #     version: "0.1",
  #     code: "1",
  #     display: "true"
  #   }
  # end

  # def status_history_factory do
  #   %StatusHistory{
  #     status: Episode.status(:active),
  #     period: build(:period),
  #     inserted_at: NaiveDateTime.utc_now(),
  #     updated_at: NaiveDateTime.utc_now()
  #   }
  # end
end
