defmodule Core.Patients.Immunizations.Reaction do
  @moduledoc false

  use Core.Schema
  alias Core.Reference

  embedded_schema do
    field(:date)
    field(:detail, reference: [path: "detail"])
    field(:reported)
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"date", v} ->
          {:date, create_datetime(v)}

        {"detail", v} ->
          {:detail, Reference.create(v)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end

defimpl Vex.Blank, for: Core.Patients.Immunizations.Reaction do
  def blank?(%Core.Patients.Immunizations.Reaction{}), do: false
  def blank?(_), do: true
end
