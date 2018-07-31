defmodule Core.Episode do
  @moduledoc false

  # use Ecto.Schema

  # alias Core.CodeableConcept
  # alias Core.Diagnosis
  # alias Core.Period
  # alias Core.StatusHistory

  # @status_active "active"
  # @status_closed "closed"
  # @status_cancelled "cancelled"

  # def status(:active), do: @status_active
  # def status(:closed), do: @status_closed
  # def status(:cancelled), do: @status_cancelled

  # @primary_key {:id, :binary_id, autogenerate: true}
  # embedded_schema do
  #   field(:status)
  #   embeds_many(:status_history, StatusHistory)
  #   embeds_one(:type, CodeableConcept)
  #   embeds_one(:diagnosis, Diagnosis)
  #   # embeds_one(:managing_organization, Organization)
  #   embeds_one(:period, Period)

  #   timestamps()
  # end
end
