defmodule Api.Web.MedicationStatementController do
  @moduledoc false

  use ApiWeb, :controller

  alias Core.Patients.MedicationStatements
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: medication_statements} = paging} <- MedicationStatements.list(params) do
      render(conn, "index.json", medication_statements: medication_statements, paging: paging)
    end
  end

  def show(conn, %{"patient_id_hash" => patient_id_hash, "id" => medication_statement_id}) do
    with {:ok, medication_statement} <- MedicationStatements.get_by_id(patient_id_hash, medication_statement_id) do
      render(conn, "show.json", medication_statement: medication_statement)
    end
  end
end
