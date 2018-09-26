defmodule Core.Patient do
  @moduledoc false

  use Core.Schema

  @status_active "active"
  @status_inactive "inactive"

  def status(:active), do: @status_active
  def status(:inactive), do: @status_inactive

  @primary_key :_id
  schema :patients do
    field(:_id)
    field(:status, presence: true)
    field(:visits)
    field(:episodes)
    field(:encounters)
    field(:immunizations)
    field(:allergy_intolerances)

    timestamps()
    changed_by()
  end
end
