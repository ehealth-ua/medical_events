defmodule Core.Visit do
  @moduledoc false

  # defstruct [:id, :inserted_at, :updated_at, :inserted_by, :updated_by, :period]

  use Ecto.Schema

  alias Core.Period

  embedded_schema do
    embeds_one(:period, Period)

    timestamps()
  end
end
