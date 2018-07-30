defmodule Core.Ecto.ChangedBy do
  @moduledoc false

  alias Ecto.UUID

  defmacro changed_by() do
    quote bind_quoted: binding() do
      Ecto.Schema.field(:inserted_by, UUID, [])
      Ecto.Schema.field(:updated_by, UUID, [])
    end
  end
end
