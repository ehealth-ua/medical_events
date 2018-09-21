defmodule Core.Visit do
  @moduledoc false

  use Core.Schema
  alias Core.Period

  embedded_schema do
    field(:id, presence: true, mongo_uuid: true)
    field(:period, reference: [path: "period"])

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"period", v} -> {:period, Period.create(v)}
        {k, v} -> {String.to_atom(k), v}
      end)
    )
  end
end
