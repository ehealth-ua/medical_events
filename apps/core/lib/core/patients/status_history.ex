defmodule Core.StatusHistory do
  @moduledoc false

  use Ecto.Schema

  alias Core.Period

  @primary_key false
  embedded_schema do
    field(:status)
    embeds_one(:period, Period)

    timestamps()
  end
end
