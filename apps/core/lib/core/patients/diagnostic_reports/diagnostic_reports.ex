defmodule Core.Patients.DiagnosticReports do
  @moduledoc false

  alias Core.DiagnosticReport
  alias Core.Encounter
  alias Core.Executor
  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients.Encounters
  alias Core.Reference
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.Source
  require Logger

  @collection Patient.metadata().collection

  def get_by_id(patient_id_hash, id) do
    with %{"diagnostic_reports" => %{^id => diagnostic_report}} <-
           Mongo.find_one(@collection, %{
             "_id" => patient_id_hash,
             "diagnostic_reports.#{id}" => %{"$exists" => true}
           }) do
      {:ok, DiagnosticReport.create(diagnostic_report)}
    else
      _ ->
        nil
    end
  end

  def fill_up_diagnostic_report_performer(
        %DiagnosticReport{source: %Source{value: %Executor{type: "reference"} = executor}} = diagnostic_report
      ) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{executor.value.identifier.value}") do
      first_name = employee.party.first_name
      second_name = employee.party.second_name
      last_name = employee.party.last_name

      %{
        diagnostic_report
        | source: %{
            diagnostic_report.source
            | value: %{
                executor
                | value: %{executor.value | display_value: "#{first_name} #{second_name} #{last_name}"}
              }
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up performer value for diagnostic report")
        diagnostic_report
    end
  end

  def fill_up_diagnostic_report_performer(%DiagnosticReport{} = diagnostic_report), do: diagnostic_report

  def fill_up_diagnostic_report_recorded_by(
        %DiagnosticReport{recorded_by: %Reference{} = recorded_by} = diagnostic_report
      ) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{recorded_by.identifier.value}") do
      first_name = employee.party.first_name
      second_name = employee.party.second_name
      last_name = employee.party.last_name

      %{diagnostic_report | recorded_by: %{recorded_by | display_value: "#{first_name} #{second_name} #{last_name}"}}
    else
      _ ->
        Logger.warn("Failed to fill up recorded_by value for diagnostic report")
        diagnostic_report
    end
  end

  def fill_up_diagnostic_report_recorded_by(%DiagnosticReport{} = diagnostic_report), do: diagnostic_report

  def fill_up_diagnostic_report_results_interpreter(
        %DiagnosticReport{results_interpreter: %Executor{type: "reference"} = results_interpreter} = diagnostic_report
      ) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{results_interpreter.value.identifier.value}") do
      first_name = employee.party.first_name
      second_name = employee.party.second_name
      last_name = employee.party.last_name

      %{
        diagnostic_report
        | results_interpreter: %{
            results_interpreter
            | value: %{results_interpreter.value | display_value: "#{first_name} #{second_name} #{last_name}"}
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up performer value for diagnostic report")
        diagnostic_report
    end
  end

  def fill_up_diagnostic_report_results_interpreter(%DiagnosticReport{} = diagnostic_report), do: diagnostic_report

  def fill_up_diagnostic_report_managing_organization(
        %DiagnosticReport{managing_organization: managing_organization} = diagnostic_report
      ) do
    with [{_, legal_entity}] <-
           :ets.lookup(:message_cache, "legal_entity_#{managing_organization.identifier.value}") do
      %{
        diagnostic_report
        | managing_organization: %{
            managing_organization
            | display_value: Map.get(legal_entity, "public_name")
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up legal_entity value for diagnostic report")
        diagnostic_report
    end
  end

  def fill_up_diagnostic_report_managing_organization(%DiagnosticReport{} = diagnostic_report), do: diagnostic_report

  def fill_up_diagnostic_report_origin_episode(%DiagnosticReport{based_on: nil} = diagnostic_report, _),
    do: diagnostic_report

  def fill_up_diagnostic_report_origin_episode(
        %DiagnosticReport{based_on: based_on} = diagnostic_report,
        patient_id_hash
      ) do
    origin_episode =
      with {:ok, %ServiceRequest{context: context}} <- ServiceRequests.get_by_id(based_on.identifier.value),
           {:ok, %Encounter{episode: episode}} <-
             Encounters.get_by_id(patient_id_hash, UUID.binary_to_string!(context.identifier.value.binary)) do
        episode
      end

    %{diagnostic_report | origin_episode: origin_episode}
  end
end
