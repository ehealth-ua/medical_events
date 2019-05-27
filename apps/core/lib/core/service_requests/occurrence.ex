defmodule Core.ServiceRequests.Occurrence do
  @moduledoc false

  use Ecto.Schema
  alias Core.Period
  import Ecto.Changeset

  @fields_required ~w()a
  @fields_optional ~w(date_time)a

  @primary_key false
  embedded_schema do
    field(:date_time, :utc_datetime_usec)
    embeds_one(:period, Period)
  end

  def changeset(%__MODULE__{} = occurrence, params) do
    occurrence
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:period, with: &Period.occurence_changeset/2)
    |> validate_change(:date_time, fn :date_time, value ->
      case Date.compare(value, Date.utc_today()) do
        :lt -> [date_time: "Occurrence date must be in the future"]
        _ -> []
      end
    end)
  end
end
