defmodule Api.Web.ConditionView do
  @moduledoc false

  use ApiWeb, :view
  alias Api.Web.ReferenceView

  def render("index.json", %{conditions: conditions}) do
    render_many(conditions, __MODULE__, "show.json", as: :condition)
  end

  def render("show.json", %{condition: condition}) do
    condition_fields = ~w(
      clinical_status
      verification_status
      primary_source
    )a

    condition_data = %{
      id: condition._id,
      body_sites: ReferenceView.render(condition.body_sites),
      severity: ReferenceView.render(condition.severity),
      stage: ReferenceView.render(condition.stage),
      code: ReferenceView.render(condition.code),
      context: ReferenceView.render(condition.context),
      evidences: ReferenceView.render(condition.evidences),
      asserted_date: Date.to_string(condition.asserted_date),
      onset_date: Date.to_string(condition.onset_date)
    }

    condition
    |> Map.take(condition_fields)
    |> Map.merge(condition_data)
    |> Map.merge(ReferenceView.render_source(condition.source))
  end
end
