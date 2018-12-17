defmodule SecondaryEventsConsumer.Kafka.Consumer do
  @moduledoc false

  alias Core.Jobs
  alias Core.Jobs.JobUpdateStatusJob
  alias Core.Jobs.PackageCancelSaveConditionsJob
  alias Core.Jobs.PackageCancelSaveObservationsJob
  alias Core.Jobs.PackageCancelSavePatientJob
  alias Core.Jobs.PackageSaveConditionsJob
  alias Core.Jobs.PackageSaveObservationsJob
  alias Core.Jobs.PackageSavePatientJob
  alias Core.Patients.Encounters.Cancel
  alias Core.Patients.Package
  require Logger

  def handle_message(%{offset: offset, value: value}) do
    value = :erlang.binary_to_term(value)
    Logger.metadata(request_id: value.request_id, job_id: value._id)
    Logger.debug(fn -> "message: " <> inspect(value) end)
    Logger.info(fn -> "offset: #{offset}" end)
    :ok = consume(value)
  end

  defp consume(%PackageSavePatientJob{} = package_save_patient_job) do
    do_consume(Package, :consume_save_patient, package_save_patient_job)
  end

  defp consume(%PackageSaveConditionsJob{} = package_save_conditions_job) do
    do_consume(Package, :consume_save_conditions, package_save_conditions_job)
  end

  defp consume(%PackageSaveObservationsJob{} = package_save_observations_job) do
    do_consume(Package, :consume_save_observations, package_save_observations_job)
  end

  defp consume(%PackageCancelSavePatientJob{} = package_cancel_save_patient_job) do
    do_consume(Cancel, :consume_save_patient, package_cancel_save_patient_job)
  end

  defp consume(%PackageCancelSaveConditionsJob{} = package_cancel_save_conditions_job) do
    do_consume(Cancel, :consume_save_conditions, package_cancel_save_conditions_job)
  end

  defp consume(%PackageCancelSaveObservationsJob{} = package_cancel_save_observations_job) do
    do_consume(Cancel, :consume_save_observations, package_cancel_save_observations_job)
  end

  defp consume(%JobUpdateStatusJob{} = job_update_status_job) do
    Jobs.update_status(job_update_status_job)
  end

  defp consume(value) do
    Logger.warn(fn ->
      "unknown kafka event #{inspect(value)}"
    end)

    :ok
  end

  defp do_consume(module, fun, %{_id: id} = kafka_job) do
    case Jobs.get_by_id(id) do
      {:ok, _} ->
        apply(module, fun, [kafka_job])

      _ ->
        response = "Can't get request by id #{id}"
        Logger.warn(fn -> response end)
        :ok
    end
  end
end
