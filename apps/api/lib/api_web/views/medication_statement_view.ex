defmodule Api.Web.MedicationStatementView do
  @moduledoc false

  use ApiWeb, :view

  alias Core.DateView
  alias Core.ReferenceView
  alias Core.UUIDView

  def render("index.json", %{medication_statements: medication_statements}) do
    render_many(medication_statements, __MODULE__, "show.json", as: :medication_statement)
  end

  def render("show.json", %{medication_statement: medication_statement}) do
    medication_statement_fields = ~w(
      status
      effective_period
      primary_source
      note
      dosage
      inserted_at
      updated_at
    )a

    medication_statement_data = %{
      id: UUIDView.render(medication_statement.id),
      based_on: ReferenceView.render(medication_statement.based_on),
      medication_code: ReferenceView.render(medication_statement.medication_code),
      context: ReferenceView.render(medication_statement.context),
      asserted_date: DateView.render_datetime(medication_statement.asserted_date)
    }

    medication_statement
    |> Map.take(medication_statement_fields)
    |> Map.merge(medication_statement_data)
    |> Map.merge(ReferenceView.render_source(medication_statement.source))
  end
end
