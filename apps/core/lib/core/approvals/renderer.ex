defmodule Core.Approvals.Renderer do
  @moduledoc false

  alias Core.Approval
  alias Core.ReferenceView
  alias Core.UUIDView

  def render(%Approval{} = approval) do
    approval_fields = ~w(
      expires_at
      status
      access_level
    )a

    approval_data = %{
      id: UUIDView.render(approval._id),
      granted_resources: ReferenceView.render(approval.granted_resources),
      granted_to: ReferenceView.render(approval.granted_to),
      reason: if(approval.reason, do: ReferenceView.render(approval.reason), else: approval.reason)
    }

    approval
    |> Map.take(approval_fields)
    |> Map.merge(approval_data)
  end
end
