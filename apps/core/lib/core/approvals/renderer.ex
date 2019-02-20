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
      reason: ReferenceView.render(approval.reason),
      authentication_method_current: approval.urgent
    }

    approval
    |> Map.take(approval_fields)
    |> Map.merge(approval_data)
  end
end
