defmodule Core.Approval do
  @moduledoc false

  use Core.Schema

  alias Core.Maybe
  alias Core.Reference

  @status_new "new"
  @status_active "active"

  @access_level_read "read"

  @primary_key :_id
  schema :approvals do
    field(:_id, presence: true)
    field(:patient_id, presence: true)

    field(:granted_resources,
      presence: true,
      reference: [path: "granted_resources"]
    )

    field(:granted_to,
      presence: true,
      reference: [path: "granted_to"]
    )

    field(:expires_at, presence: true)

    field(:granted_by,
      presence: true,
      reference: [path: "granted_by"]
    )

    field(:reason, reference: [path: "reason"])
    field(:status, presence: true, inclusion: [@status_new, @status_active])
    field(:access_level, presence: true, inclusion: [@access_level_read])
    field(:urgent, presence: true)

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"id", v} ->
          {:_id, v}

        {"granted_resources", v} ->
          {:granted_resources, Enum.map(v, &Reference.create/1)}

        {"granted_to", v} ->
          {:granted_to, Maybe.map(v, &Reference.create/1)}

        {"granted_by", v} ->
          {:granted_by, Maybe.map(v, &Reference.create/1)}

        {"reason", nil} ->
          {:reason, nil}

        {"reason", v} ->
          {:reason, Maybe.map(v, &Reference.create/1)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end

  def status(:new), do: @status_new
  def status(:active), do: @status_active

  def access_level(:read), do: @access_level_read
end
