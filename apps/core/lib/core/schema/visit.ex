defmodule Core.Schema.Visit do
  @moduledoc false

  require Core.Keyspaces.Events

  use Triton.CustomType

  custom_type :visit, keyspace: Core.Keyspaces.Events do
    # validators using vex
    # field(:visits, {:list, "<FROZEN<visit>>"})
    # # field(:visits, {:map, "<text, FROZEN<period>>"})
    field(:inserted_at, :timestamp)
    field(:updated_at, :timestamp)
    field(:updated_by, :text, validators: [uuid: true])
    field(:inserted_by, :text, validators: [uuid: true])
    field(:period, "FROZEN<period>")
  end

  # defstruct [:id, :inserted_at, :updated_at, :inserted_by, :updated_by, :period]
end
