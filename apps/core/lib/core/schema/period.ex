defmodule Core.Period do
  @moduledoc false

  use Ecto.Schema
  alias Ecto.Changeset
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:start, :utc_datetime)
    field(:end, :utc_datetime)
  end

  @fields_required ~w(start)a
  @fields_optional ~w(end)a

  def changeset(%__MODULE__{} = period, params) do
    period
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> validate_change(:start, fn :start, value ->
      case DateTime.compare(value, DateTime.utc_now()) do
        :gt -> [start: "Start date must be in past"]
        _ -> []
      end
    end)
    |> validate_end_date()
  end

  def occurence_changeset(%__MODULE__{} = period, params) do
    period
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> validate_change(:start, fn :start, value ->
      case DateTime.compare(value, DateTime.utc_now()) do
        :lt -> [start: "Occurrence start date must be in the future"]
        _ -> []
      end
    end)
    |> validate_occurence_end_date()
  end

  defp validate_end_date(%Changeset{valid?: true} = changeset) do
    start = get_change(changeset, :start)

    validate_change(changeset, :end, fn :end, value ->
      cond do
        DateTime.compare(value, DateTime.utc_now()) == :gt -> [end: "End date must be in past"]
        start && DateTime.compare(value, start) == :lt -> [end: "End date must be greater than or equal the start date"]
        true -> []
      end
    end)
  end

  defp validate_end_date(changeset), do: changeset

  defp validate_occurence_end_date(%Changeset{valid?: true} = changeset) do
    start = get_change(changeset, :start)

    validate_change(changeset, :end, fn :end, value ->
      if DateTime.compare(value, start) == :lt do
        [end: "End date must be greater than or equal the start date"]
      else
        []
      end
    end)
  end

  defp validate_occurence_end_date(changeset), do: changeset
end
