defmodule Core.Patients.DiagnosticReports do
  @moduledoc false

  alias Core.DiagnosticReport
  alias Core.Encounter
  alias Core.Executor
  alias Core.Jobs
  alias Core.Jobs.DiagnosticReportPackageCreateJob
  alias Core.Maybe
  alias Core.Mongo
  alias Core.Observation
  alias Core.Observations.Validations, as: ObservationValidations
  alias Core.Paging
  alias Core.Patient
  alias Core.Patients
  alias Core.Patients.DiagnosticReports.Package
  alias Core.Patients.DiagnosticReports.Validations, as: DiagnosticReportValidations
  alias Core.Patients.Encounters
  alias Core.Patients.Encounters.Validations, as: EncounterValidations
  alias Core.Patients.Validators
  alias Core.Reference
  alias Core.Search
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.Source
  alias Core.Validators.JsonSchema
  alias Core.Validators.OneOf
  alias Core.Validators.Signature
  alias EView.Views.ValidationError
  alias Scrivener.Page
  require Logger

  @collection Patient.metadata().collection
  @digital_signature Application.get_env(:core, :microservices)[:digital_signature]
  @media_storage Application.get_env(:core, :microservices)[:media_storage]
  @kafka_producer Application.get_env(:core, :kafka)[:producer]

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
    "$.diagnostic_report.results_interpreter" => %{"params" => ["reference", "text"], "required" => true},
    "$.diagnostic_report.performer" => %{"params" => ["reference", "text"], "required" => true}
  }

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

  def get_summary(patient_id_hash, id) do
    with %{"diagnostic_reports" => %{^id => diagnostic_report}} <-
           Mongo.find_one(@collection, %{
             "_id" => patient_id_hash,
             "diagnostic_reports.#{id}" => %{"$exists" => true},
             "diagnostic_reports.#{id}.conclusion_code.coding.code" => %{
               "$in" => Confex.fetch_env!(:core, :summary)[:diagnostic_reports_whitelist]
             }
           }) do
      {:ok, DiagnosticReport.create(diagnostic_report)}
    else
      _ ->
        nil
    end
  end

  def list(%{"patient_id_hash" => patient_id_hash} = params, schema \\ :diagnostic_report_request) do
    with :ok <- JsonSchema.validate(schema, Map.drop(params, ~w(page page_size patient_id patient_id_hash))) do
      pipeline =
        [
          %{"$match" => %{"_id" => patient_id_hash}},
          %{"$project" => %{"diagnostic_reports" => %{"$objectToArray" => "$diagnostic_reports"}}},
          %{"$unwind" => "$diagnostic_reports"}
        ]
        |> add_search_pipeline(patient_id_hash, params, schema)
        |> Enum.concat([
          %{"$project" => %{"diagnostic_report" => "$diagnostic_reports.v"}},
          %{"$replaceRoot" => %{"newRoot" => "$diagnostic_report"}},
          %{"$sort" => %{"inserted_at" => -1}}
        ])

      with %Page{entries: diagnostic_reports} = paging <-
             Paging.paginate(:aggregate, @collection, pipeline, Map.take(params, ~w(page page_size))) do
        {:ok, %Page{paging | entries: Enum.map(diagnostic_reports, &DiagnosticReport.create/1)}}
      end
    end
  end

  defp add_search_pipeline(pipeline, patient_id_hash, params, schema) do
    path = "diagnostic_reports.v"
    encounter_id = Maybe.map(params["encounter_id"], &Mongo.string_to_uuid(&1))
    issued_from = Search.get_filter_date(:from, params["issued_from"])
    issued_to = Search.get_filter_date(:to, params["issued_to"])

    context_episode_id = if params["context_episode_id"], do: Mongo.string_to_uuid(params["context_episode_id"])
    origin_episode_id = if params["origin_episode_id"], do: Mongo.string_to_uuid(params["origin_episode_id"])
    encounter_ids = if !is_nil(context_episode_id), do: get_encounter_ids(patient_id_hash, context_episode_id)

    search_pipeline =
      %{"$match" => %{}}
      |> Search.add_param(
        %{"code" => params["code"]},
        ["$match", "#{path}.code.coding"],
        "$elemMatch"
      )
      |> Search.add_param(encounter_id, ["$match", "#{path}.encounter.identifier.value"])
      |> add_search_param(encounter_ids, ["$match", "#{path}.encounter.identifier.value"], "$in")
      |> Search.add_param(issued_from, ["$match", "#{path}.issued"], "$gte")
      |> Search.add_param(issued_to, ["$match", "#{path}.issued"], "$lt")
      |> Search.add_param(origin_episode_id, ["$match", "#{path}.origin_episode.identifier.value"])

    search_pipeline =
      if schema == :diagnostic_report_summary do
        Search.add_param(
          search_pipeline,
          Confex.fetch_env!(:core, :summary)[:diagnostic_reports_whitelist],
          ["$match", "#{path}.conclusion_code.coding.code"],
          "$in"
        )
      else
        search_pipeline
      end

    search_pipeline
    |> Map.get("$match", %{})
    |> Map.keys()
    |> case do
      [] -> pipeline
      _ -> pipeline ++ [search_pipeline]
    end
  end

  def get_encounter_ids(patient_id_hash, episode_id) do
    patient_id_hash
    |> Encounters.get_episode_encounters(episode_id)
    |> Enum.map(& &1["encounter_id"])
    |> Enum.uniq()
  end

  defp add_search_param(search_params, nil, _path, _operator), do: search_params

  defp add_search_param(search_params, value, path, operator) do
    if get_in(search_params, path) == nil do
      put_in(search_params, path, %{operator => value})
    else
      update_in(search_params, path, &Map.merge(&1, %{operator => value}))
    end
  end

  def get_by_encounter_id(patient_id_hash, %BSON.Binary{} = encounter_id) do
    @collection
    |> Mongo.aggregate([
      %{"$match" => %{"_id" => patient_id_hash}},
      %{"$project" => %{"diagnostic_reports" => %{"$objectToArray" => "$diagnostic_reports"}}},
      %{"$unwind" => "$diagnostic_reports"},
      %{"$match" => %{"diagnostic_reports.v.encounter.identifier.value" => encounter_id}},
      %{"$replaceRoot" => %{"newRoot" => "$diagnostic_reports.v"}}
    ])
    |> Enum.map(&DiagnosticReport.create/1)
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

  def produce_create_package(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:diagnostic_report_package_create, Map.take(params, ["signed_data"])),
         {:ok, job, diagnostic_report_package_create_job} <-
           Jobs.create(
             DiagnosticReportPackageCreateJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(diagnostic_report_package_create_job) do
      {:ok, job}
    end
  end

  def consume_create_package(
        %DiagnosticReportPackageCreateJob{
          patient_id: patient_id,
          user_id: user_id
        } = job
      ) do
    with {:ok, data} <- decode_signed_data(job.signed_data),
         {:ok, %{"content" => content, "signer" => signer}} <- validate_signed_data(data),
         :ok <- JsonSchema.validate(:diagnostic_report_package_create_signed_content, content),
         :ok <- OneOf.validate(content, @one_of_request_params),
         employee_id <- get_in(content, ["diagnostic_report", "recorded_by", "identifier", "value"]),
         :ok <- validate_signatures(signer, employee_id, user_id, job.client_id) do
      with {:ok, observations} <- create_observations(job, content),
           {:ok, diagnostic_report} <- create_diagnostic_report(job, content) do
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

          result =
            Package.save(
              job,
              %{
                "diagnostic_report" => diagnostic_report,
                "observations" => observations
              }
            )

          case result do
            :ok ->
              :ok

            {:error, reason} ->
              Jobs.produce_update_status(job._id, job.request_id, reason, 500)
          end
        else
          error ->
            Logger.error("Failed to save signed content: #{inspect(error)}")
            Jobs.produce_update_status(job._id, job.request_id, "Failed to save signed content", 500)
        end
      else
        {:error, error, status_code} ->
          Jobs.produce_update_status(job._id, job.request_id, error, status_code)

        {:error, error} ->
          Jobs.produce_update_status(
            job._id,
            job.request_id,
            ValidationError.render("422.json", %{schema: Mongo.vex_to_json(error)}),
            422
          )
      end
    else
      {:error, %{"error" => error, "meta" => _}} ->
        Jobs.produce_update_status(job._id, job.request_id, error, 422)

      {:error, error} ->
        Jobs.produce_update_status(job._id, job.request_id, ValidationError.render("422.json", %{schema: error}), 422)

      {:error, {:bad_request, error}} ->
        Jobs.produce_update_status(job._id, job.request_id, error, 422)

      {_, response, status} ->
        Jobs.produce_update_status(job._id, job.request_id, response, status)
    end
  end

  defp create_diagnostic_report(
         %DiagnosticReportPackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"diagnostic_report" => diagnostic_report}
       ) do
    now = DateTime.utc_now()

    diagnostic_report = DiagnosticReport.create(diagnostic_report)

    diagnostic_report =
      %{
        diagnostic_report
        | inserted_at: now,
          updated_at: now,
          inserted_by: user_id,
          updated_by: user_id
      }
      |> DiagnosticReportValidations.validate_based_on(client_id)
      |> DiagnosticReportValidations.validate_effective()
      |> DiagnosticReportValidations.validate_issued()
      |> DiagnosticReportValidations.validate_recorded_by(client_id)
      |> DiagnosticReportValidations.validate_source(client_id)
      |> DiagnosticReportValidations.validate_managing_organization(client_id)
      |> DiagnosticReportValidations.validate_results_interpreter(client_id)

    case Vex.errors(
           %{diagnostic_report: diagnostic_report},
           diagnostic_report: [
             reference: [path: "diagnostic_report"]
           ]
         ) do
      [] ->
        validate_diagnostic_report(patient_id_hash, diagnostic_report)

      errors ->
        {:error, errors}
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
        observation =
          data
          |> Map.drop(["reaction_on"])
          |> Observation.create()

        %{
          observation
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id,
            patient_id: patient_id_hash
        }
        |> ObservationValidations.validate_issued()
        |> ObservationValidations.validate_effective_at()
        |> ObservationValidations.validate_source(client_id)
        |> ObservationValidations.validate_value()
        |> ObservationValidations.validate_components()
      end)

    case Vex.errors(
           %{observations: observations},
           observations: [unique_ids: [field: :_id], reference: [path: "observations"]]
         ) do
      [] ->
        validate_observations(observations)

      errors ->
        {:error, errors}
    end
  end

  defp create_observations(_, _), do: {:ok, []}

  defp validate_diagnostic_report(patient_id_hash, diagnostic_report) do
    case get_by_id(patient_id_hash, diagnostic_report.id) do
      {:ok, _} ->
        {:error, "Diagnostic report with id '#{diagnostic_report.id}' already exists", 409}

      _ ->
        {:ok, diagnostic_report}
    end
  end

  defp validate_observations(observations) do
    Enum.reduce_while(observations, {:ok, observations}, fn observation, acc ->
      if Mongo.find_one(
           Observation.metadata().collection,
           %{"_id" => Mongo.string_to_uuid(observation._id)},
           projection: %{"_id" => true}
         ) do
        {:halt, {:error, "Observation with id '#{observation._id}' already exists", 409}}
      else
        {:cont, acc}
      end
    end)
  end

  defp decode_signed_data(signed_data) do
    with {:ok, %{"data" => data}} <- @digital_signature.decode(signed_data, []) do
      {:ok, data}
    else
      {:error, %{"error" => _} = error} ->
        Logger.info(inspect(error))
        {:error, "Invalid signed content", 422}

      error ->
        Logger.error(inspect(error))
        {:ok, "Failed to decode signed content", 500}
    end
  end

  defp validate_signed_data(signed_data) do
    with {:ok, %{"content" => _, "signer" => _}} = validation_result <- Signature.validate(signed_data) do
      validation_result
    else
      {:error, error} -> {:error, error, 422}
    end
  end

  defp validate_signatures(signer, employee_id, user_id, client_id) do
    case EncounterValidations.validate_signatures(signer, employee_id, user_id, client_id) do
      :ok -> :ok
      {:error, error} -> {:ok, error, 409}
    end
  end
end
