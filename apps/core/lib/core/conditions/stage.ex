defmodule Core.Stage do
  @moduledoc false

  use Ecto.Schema

  alias Code.CodeableConcept

  embedded_schema do
    embeds_one(:summary, CodeableConcept)

    timestamps()
  end
end
