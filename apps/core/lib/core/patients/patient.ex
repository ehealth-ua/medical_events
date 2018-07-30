defmodule Core.Patient do
  @moduledoc false

  use Ecto.Schema

  alias Core.Episode
  alias Core.Visit
  import Core.Ecto.ChangedBy

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "patients" do
    embeds_many(:visits, Visit)
    embeds_many(:episodes, Episode)

    timestamps()
    changed_by()
  end
end
