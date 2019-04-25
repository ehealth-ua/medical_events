defmodule Api.Web.DiagnosticReportController do
  @moduledoc false

  use ApiWeb, :controller

  alias Api.Web.JobView
  alias Core.Patients.DiagnosticReports
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: diagnostic_reports} = paging} <- DiagnosticReports.list(params) do
      render(conn, "index.json", diagnostic_reports: diagnostic_reports, paging: paging)
    end
  end

  def show(conn, %{"patient_id_hash" => patient_id_hash, "id" => diagnostic_report_id}) do
    with {:ok, diagnostic_report} <- DiagnosticReports.get_by_id(patient_id_hash, diagnostic_report_id) do
      render(conn, "show.json", diagnostic_report: diagnostic_report)
    end
  end

  def create(conn, params) do
    with {:ok, job} <-
           DiagnosticReports.produce_create_package(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("details.json", job: job)
    end
  end

  def cancel(conn, params) do
    with {:ok, job} <-
           DiagnosticReports.produce_cancel_package(params, conn.private[:user_id], conn.private[:client_id]) do
      conn
      |> put_status(202)
      |> put_view(JobView)
      |> render("details.json", job: job)
    end
  end
end
