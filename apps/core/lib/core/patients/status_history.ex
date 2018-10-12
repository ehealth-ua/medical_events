defmodule Core.StatusHistory do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept

  embedded_schema do
    field(:status, presence: true)
    field(:status_reason)
    field(:inserted_at, presence: true)
    field(:inserted_by, presence: true, uuid: true)
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"status_reason", nil} ->
          {:status_reason, nil}

        {"status_reason", v} ->
          {:status_reason, CodeableConcept.create(v)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
