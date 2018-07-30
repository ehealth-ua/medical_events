defmodule Core.Factories do
  @moduledoc false

  # use ExMachina

  # alias Ecto.UUID
  # alias Core.CodeableConcept
  # alias Core.Coding
  # alias Core.Episode
  # alias Core.Period
  # alias Core.StatusHistory
  # alias Core.Visit
  use Core.Factories.Patient
  use Core.Factories.Period

  def insert(type, params \\ []) do
    apply(__MODULE__, String.to_atom("save_#{type}_factory"), [params]) |> IO.inspect()
  end

  def build(type, params \\ []) do
    apply(__MODULE__, String.to_atom("#{type}_factory"), [params])
  end

  # def period_factory do
  #   %Period{
  #     start: NaiveDateTime.utc_now(),
  #     end: NaiveDateTime.utc_now()
  #   }
  # end

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
