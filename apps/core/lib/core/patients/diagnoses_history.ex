defmodule Core.DiagnosesHistory do
  @moduledoc false

  use Core.Schema
  alias Core.Diagnosis
  alias Core.Reference

  embedded_schema do
    field(:date, presence: true)
    field(:evidence, presence: true, reference: [path: "evidence"])
    field(:diagnoses, presence: true, reference: [path: "diagnoses"])
    field(:is_active, strict_presence: true)
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"evidence", v} ->
          {:evidence, Reference.create(v)}

        {"date", v} ->
          {:date, create_datetime(v)}

        {"diagnoses", v} ->
          {:diagnoses, Enum.map(v, &Diagnosis.create/1)}

        {"is_active", v} ->
          {:is_active, v}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
