defmodule Core.Patients.MedicationStatements do
  @moduledoc false

  alias Core.MedicationStatement
  alias Core.Mongo
  alias Core.Patient
  alias Core.Source
  require Logger

  @collection Patient.metadata().collection

  def get_by_id(patient_id_hash, id) do
    with %{"medication_statements" => %{^id => medication_statement}} <-
           Mongo.find_one(@collection, %{
             "_id" => patient_id_hash,
             "medication_statements.#{id}" => %{"$exists" => true}
           }) do
      {:ok, MedicationStatement.create(medication_statement)}
    else
      _ ->
        nil
    end
  end

  def fill_up_medication_statement_asserter(
        %MedicationStatement{source: %Source{type: "report_origin"}} = medication_statement
      ),
      do: medication_statement

  def fill_up_medication_statement_asserter(%MedicationStatement{source: %Source{value: value}} = medication_statement) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{value.identifier.value}") do
      first_name = employee.party.first_name
      second_name = employee.party.second_name
      last_name = employee.party.last_name

      %{
        medication_statement
        | source: %{
            medication_statement.source
            | value: %{
                value
                | display_value: "#{first_name} #{second_name} #{last_name}"
              }
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up employee value for medication statement")
        medication_statement
    end
  end
end
