defmodule Core.ServiceRequestView do
  @moduledoc false

  alias Core.DateView
  alias Core.Encryptor
  alias Core.Reference
  alias Core.ReferenceView
  alias Core.ServiceRequest
  alias Core.StatusHistoryView
  alias Core.UUIDView

  def render_service_request(%ServiceRequest{} = service_request) do
    service_request
    |> Map.take(~w(
      status
      intent
      explanator_letter
      authored_on
      note
      patient_instruction
      expiration_date
      priority
    )a)
    |> Map.merge(%{
      id: to_string(service_request._id),
      category: ReferenceView.render(service_request.category),
      code: ReferenceView.render(service_request.code),
      context: ReferenceView.render(service_request.context),
      requester_employee: ReferenceView.render(service_request.requester_employee),
      requester_legal_entity: ReferenceView.render(service_request.requester_legal_entity),
      performer_type: ReferenceView.render(service_request.performer_type),
      reason_reference: ReferenceView.render(service_request.reason_reference),
      supporting_info: ReferenceView.render(service_request.supporting_info),
      permitted_resources: ReferenceView.render(service_request.permitted_resources),
      used_by_employee: ReferenceView.render(service_request.used_by_employee),
      used_by_legal_entity: ReferenceView.render(service_request.used_by_legal_entity),
      subject:
        ReferenceView.render(
          Reference.create(%{
            "identifier" => %{
              "type" => %{
                "coding" => [%{"system" => "eHealth/resources", "code" => "patient"}],
                "text" => ""
              },
              "value" => UUIDView.render(Encryptor.decrypt(service_request.subject))
            }
          })
        ),
      inserted_at: DateView.render_datetime(service_request.inserted_at),
      updated_at: DateView.render_datetime(service_request.updated_at),
      status_history: StatusHistoryView.render("index.json", %{statuses_history: service_request.status_history}),
      status_reason: ReferenceView.render(service_request.status_reason),
      completed_with: ReferenceView.render(service_request.completed_with),
      requisition: Encryptor.decrypt(service_request.requisition)
    })
    |> Map.merge(ReferenceView.render_occurrence(service_request.occurrence))
  end
end
