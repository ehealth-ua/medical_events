defmodule Api.Web.ServiceRequestView do
  @moduledoc false

  use ApiWeb, :view

  alias Core.ReferenceView
  alias Core.UUIDView

  def render("index.json", %{service_requests: service_requests}) do
    render_many(service_requests, __MODULE__, "show.json", as: :service_request)
  end

  def render("show.json", %{service_request: service_request}) do
    service_request
    |> Map.take(~w(
      requisition
      status
      status_reason
      intent
      explanator_letter
      authored_on
      note
      patient_instruction
      expiration_date
    )a)
    |> Map.merge(%{
      id: to_string(service_request._id),
      category: ReferenceView.render(service_request.category),
      status_history: ReferenceView.render(service_request.status_history),
      code: ReferenceView.render(service_request.code),
      subject: UUIDView.render(service_request.subject),
      context: ReferenceView.render(service_request.context),
      requester: ReferenceView.render(service_request.requester),
      performer_type: ReferenceView.render(service_request.performer_type),
      reason_reference: ReferenceView.render(service_request.reason_reference),
      supporting_info: ReferenceView.render(service_request.supporting_info),
      permitted_episodes: ReferenceView.render(service_request.permitted_episodes),
      used_by: ReferenceView.render(service_request.used_by)
    })
    |> Map.merge(ReferenceView.render_occurence(service_request.occurence))
  end
end
