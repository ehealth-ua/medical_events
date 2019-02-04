defmodule Api.Web.ApprovalView do
  @moduledoc false

  use ApiWeb, :view

  alias Core.ReferenceView
  alias Core.UUIDView

  def render("empty.json", _), do: %{}

  def render("index.json", %{approvals: approvals}) do
    render_many(approvals, __MODULE__, "show.json", as: :approval)
  end

  def render("show.json", %{approval: approval}) do
    fields = ~w(
      access_level
      reason
      status
      inserted_at
      updated_at
      urgent
    )a

    approval_data = %{
      id: UUIDView.render(approval._id),
      granted_by: ReferenceView.render(approval.granted_by),
      granted_resources: ReferenceView.render(approval.granted_resources),
      granted_to: ReferenceView.render(approval.granted_to)
    }

    approval
    |> Map.take(fields)
    |> Map.merge(approval_data)
  end
end
