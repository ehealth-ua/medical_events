defmodule Core.CodeableConcept do
  @moduledoc false

  use Ecto.Schema

  alias Core.Coding

  @primary_key false
  embedded_schema do
    embeds_one(:coding, Coding)
    field(:text)
  end
end
