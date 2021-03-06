defmodule Core.Patients.DiagnosticReports.Consumer do
  @moduledoc false

  alias Core.DiagnosticReport
  alias Core.DigitalSignature
  alias Core.Jobs
  alias Core.Jobs.DiagnosticReportPackageCancelJob
  alias Core.Jobs.DiagnosticReportPackageCreateJob
  alias Core.Mongo
  alias Core.Observation
  alias Core.Patients
  alias Core.Patients.DiagnosticReports
  alias Core.Patients.DiagnosticReports.Cancel, as: CancelDiagnosticReport
  alias Core.Patients.DiagnosticReports.Package
  alias Core.Patients.Encounters.Validations, as: EncounterValidations
  alias Core.ValidationError, as: CoreValidationError
  alias Core.Validators.Error
  alias Core.Validators.JsonSchema
  alias Core.Validators.OneOf
  alias Ecto.Changeset
  alias EView.Views.ValidationError
  require Logger

  @media_storage Application.get_env(:core, :microservices)[:media_storage]

  @one_of_request_params %{
    "$.observations" => [
      %{"params" => ["effective_date_time", "effective_period"], "required" => false},
      %{
        "params" => [
          "value_quantity",
          "value_codeable_concept",
          "value_sampled_data",
          "value_string",
          "value_boolean",
          "value_range",
          "value_ratio",
          "value_time",
          "value_date_time",
          "value_period"
        ],
        "required" => true
      }
    ],
    "$.observations.components" => %{
      "params" => [
        "value_quantity",
        "value_codeable_concept",
        "value_sampled_data",
        "value_string",
        "value_boolean",
        "value_range",
        "value_ratio",
        "value_time",
        "value_date_time",
        "value_period"
      ],
      "required" => true
    },
    "$.diagnostic_report.results_interpreter" => %{
      "params" => ["reference", "text"],
      "required" => true
    },
    "$.diagnostic_report.performer" => %{"params" => ["reference", "text"], "required" => true}
  }

  def consume_create_package(
        %DiagnosticReportPackageCreateJob{
          patient_id: patient_id,
          user_id: user_id
        } = job
      ) do
    with {:ok, %{content: content, signer: signer}} <- DigitalSignature.decode_and_validate(job.signed_data),
         :ok <- JsonSchema.validate(:diagnostic_report_package_create_signed_content, content),
         :ok <- OneOf.validate(content, @one_of_request_params),
         employee_id <-
           get_in(content, ["diagnostic_report", "recorded_by", "identifier", "value"]),
         :ok <- validate_signatures(signer, employee_id, user_id, job.client_id) do
      with {:ok, observations} <- create_observations(job, content),
           {:ok, diagnostic_report} <- create_diagnostic_report(job, content, observations) do
        resource_name = "#{diagnostic_report.id}/create"
        files = [{'signed_content.txt', job.signed_data}]
        {:ok, {_, compressed_content}} = :zip.create("signed_content.zip", files, [:memory])

        with :ok <-
               @media_storage.save(
                 patient_id,
                 compressed_content,
                 Confex.fetch_env!(:core, Core.Microservices.MediaStorage)[:diagnostic_report_bucket],
                 resource_name
               ) do
          diagnostic_report = %{diagnostic_report | signed_content_links: [resource_name]}

          Package.save(
            job,
            %{
              "diagnostic_report" => diagnostic_report,
              "observations" => observations
            }
          )
        else
          _ ->
            Jobs.produce_update_status(job, "Failed to save signed content", 500)
        end
      else
        %Changeset{valid?: false} = changeset ->
          Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)

        {:error, error, status_code} ->
          Jobs.produce_update_status(job, error, status_code)
      end
    else
      {:error, error} ->
        Jobs.produce_update_status(job, ValidationError.render("422.json", %{schema: error}), 422)

      {:error, {:bad_request, error}} ->
        Jobs.produce_update_status(job, error, 422)

      {_, response, status} ->
        Jobs.produce_update_status(job, response, status)
    end
  end

  def consume_cancel_package(
        %DiagnosticReportPackageCancelJob{patient_id_hash: patient_id_hash, user_id: user_id} = job
      ) do
    with {:ok, %{content: content, signer: signer}} <- DigitalSignature.decode_and_validate(job.signed_data),
         :ok <- JsonSchema.validate(:diagnostic_report_package_cancel_signed_content, content),
         :ok <- OneOf.validate(content, @one_of_request_params),
         employee_id <- get_in(content, ["encounter", "performer", "identifier", "value"]),
         diagnostic_report_id <- content["diagnostic_report"]["id"],
         :ok <- validate_signatures(signer, employee_id, user_id, job.client_id),
         {_, %{}} <- {:patient, Patients.get_by_id(patient_id_hash, projection: [_id: true])},
         {_, {:ok, %DiagnosticReport{} = diagnostic_report}} <-
           {:diagnostic_report, DiagnosticReports.get_by_id(patient_id_hash, diagnostic_report_id)},
         :ok <- CancelDiagnosticReport.validate(content, diagnostic_report, patient_id_hash),
         :ok <- CancelDiagnosticReport.save(content, diagnostic_report_id, job) do
      :ok
    else
      {:patient, _} ->
        Jobs.produce_update_status(job, "Patient not found", 404)

      {:diagnostic_report, _} ->
        Jobs.produce_update_status(job, "Diagnostic report not found", 404)

      {:error, error} ->
        Jobs.produce_update_status(job, ValidationError.render("422.json", %{schema: error}), 422)

      {_, response, status_code} ->
        Jobs.produce_update_status(job, response, status_code)
    end
  end

  defp create_diagnostic_report(
         %DiagnosticReportPackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"diagnostic_report" => _} = content,
         observations
       ) do
    now = DateTime.utc_now()

    changeset =
      Package.diagnostic_report_changeset(
        %Package{},
        %{
          "diagnostic_report" =>
            Map.merge(content["diagnostic_report"], %{
              "inserted_at" => now,
              "updated_at" => now,
              "inserted_by" => user_id,
              "updated_by" => user_id
            })
        },
        client_id,
        observations
      )

    case changeset do
      %Changeset{valid?: false} ->
        changeset

      _ ->
        package = Changeset.apply_changes(changeset)
        validate_diagnostic_report(patient_id_hash, package.diagnostic_report)
    end
  end

  defp create_observations(
         %DiagnosticReportPackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"observations" => _} = content
       ) do
    now = DateTime.utc_now()

    observations =
      Enum.map(content["observations"], fn data ->
        data
        |> Map.drop(["reaction_on"])
        |> Map.merge(%{
          "inserted_at" => now,
          "updated_at" => now,
          "inserted_by" => user_id,
          "updated_by" => user_id,
          "patient_id" => patient_id_hash,
          "context_episode_id" => nil,
          "effective_at" => Map.take(data, ~w(effective_date_time effective_period)),
          "value" => Map.take(data, ~w(
            value_string
            value_time
            value_boolean
            value_date_time
            value_quantity
            value_codeable_concept
            value_sampled_data
            value_range
            value_ratio
            value_period
          )),
          "source" => Map.take(data, ~w(report_origin performer))
        })
      end)

    changeset =
      Package.observations_changeset(
        %Package{},
        %{"observations" => observations},
        content["diagnostic_report"]["id"],
        client_id
      )

    case changeset do
      %Changeset{valid?: false} ->
        changeset

      _ ->
        package = Changeset.apply_changes(changeset)
        validate_observations(package.observations)
    end
  end

  defp create_observations(_, _), do: {:ok, []}

  defp validate_signatures(signer, employee_id, user_id, client_id) do
    case EncounterValidations.validate_signatures(signer, employee_id, user_id, client_id) do
      :ok -> :ok
      {:error, error} -> {:ok, error, 409}
      error -> error
    end
  end

  defp validate_diagnostic_report(patient_id_hash, diagnostic_report) do
    case DiagnosticReports.get_by_id(patient_id_hash, diagnostic_report.id) do
      {:ok, _} ->
        {:error, error} =
          Error.dump(%CoreValidationError{
            description: "Diagnostic report with id '#{diagnostic_report.id}' already exists",
            path: "$.diagnostic_report.id"
          })

        {:error, ValidationError.render("422.json", %{schema: error}), 422}

      _ ->
        {:ok, diagnostic_report}
    end
  end

  defp validate_observations(observations) do
    observations
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, observations}, fn {observation, i}, acc ->
      if Mongo.find_one(
           Observation.collection(),
           %{"_id" => Mongo.string_to_uuid(observation._id)},
           projection: %{"_id" => true}
         ) do
        {:error, error} =
          Error.dump(%CoreValidationError{
            description: "Observation with id '#{observation._id}' already exists",
            path: "$.observations.#{i}.id"
          })

        {:halt, {:error, ValidationError.render("422.json", %{schema: error}), 422}}
      else
        {:cont, acc}
      end
    end)
  end
end
