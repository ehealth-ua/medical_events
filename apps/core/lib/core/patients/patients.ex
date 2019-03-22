defmodule Core.Patients do
  @moduledoc false

  use Confex, otp_app: :core

  alias Core.AllergyIntolerance
  alias Core.Condition
  alias Core.Conditions.Validations, as: ConditionValidations
  alias Core.Device
  alias Core.DiagnosticReport
  alias Core.Encounter
  alias Core.Episode
  alias Core.Immunization
  alias Core.Jobs
  alias Core.Jobs.PackageCancelJob
  alias Core.Jobs.PackageCreateJob
  alias Core.MedicationStatement
  alias Core.Mongo
  alias Core.Observation
  alias Core.Observations.Validations, as: ObservationValidations
  alias Core.Patient
  alias Core.Patients.AllergyIntolerances
  alias Core.Patients.AllergyIntolerances.Validations, as: AllergyIntoleranceValidations
  alias Core.Patients.Devices
  alias Core.Patients.Devices.Validations, as: DeviceValidations
  alias Core.Patients.DiagnosticReports
  alias Core.Patients.DiagnosticReports.Validations, as: DiagnosticReportValidations
  alias Core.Patients.Encounters
  alias Core.Patients.Encounters.Cancel, as: CancelEncounter
  alias Core.Patients.Encounters.Validations, as: EncounterValidations
  alias Core.Patients.Encryptor
  alias Core.Patients.Episodes
  alias Core.Patients.Immunizations
  alias Core.Patients.Immunizations.Reaction
  alias Core.Patients.Immunizations.Validations, as: ImmunizationValidations
  alias Core.Patients.MedicationStatements
  alias Core.Patients.MedicationStatements.Validations, as: MedicationStatementValidations
  alias Core.Patients.Package
  alias Core.Patients.RiskAssessments
  alias Core.Patients.RiskAssessments.Validations, as: RiskAssessmentValidations
  alias Core.Patients.Validators
  alias Core.Patients.Visits.Validations, as: VisitValidations
  alias Core.RiskAssessment
  alias Core.Validators.JsonSchema
  alias Core.Validators.OneOf
  alias Core.Validators.Signature
  alias Core.Validators.Vex
  alias Core.Visit
  alias EView.Views.ValidationError

  require Logger

  @collection Patient.metadata().collection
  @digital_signature Application.get_env(:core, :microservices)[:digital_signature]
  @media_storage Application.get_env(:core, :microservices)[:media_storage]
  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  @one_of_request_params %{
    "$.conditions" => %{"params" => ["report_origin", "asserter"], "required" => true},
    "$.observations" => [
      %{"params" => ["report_origin", "performer"], "required" => true},
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
    "$.immunizations" => %{"params" => ["report_origin", "performer"], "required" => true},
    "$.immunizations.explanation" => %{"params" => ["reasons", "reasons_not_given"], "required" => false},
    "$.allergy_intolerances" => %{"params" => ["report_origin", "asserter"], "required" => true},
    "$.risk_assessments.predictions" => [
      %{"params" => ["probability_range", "probability_decimal"], "required" => false},
      %{"params" => ["when_range", "when_period"], "required" => false}
    ],
    "$.devices" => %{"params" => ["report_origin", "asserter"], "required" => true},
    "$.medication_statements" => %{"params" => ["report_origin", "asserter"], "required" => true}
  }

  def get_pk_hash(nil), do: nil

  def get_pk_hash(value) do
    Encryptor.encrypt(value)
  end

  def get_by_id(id) do
    Mongo.find_one(@collection, %{"_id" => id})
  end

  def produce_create_package(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:package_create, Map.take(params, ["signed_data", "visit"])),
         {:ok, job, package_create_job} <-
           Jobs.create(
             PackageCreateJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(package_create_job) do
      {:ok, job}
    end
  end

  def produce_cancel_package(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with :ok <- JsonSchema.validate(:package_cancel, Map.take(params, ["signed_data"])),
         %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient) do
      job_data =
        params
        |> Map.put("user_id", user_id)
        |> Map.put("client_id", client_id)

      with {:ok, job, package_cancel_job} <- Jobs.create(PackageCancelJob, job_data),
           :ok <- @kafka_producer.publish_medical_event(package_cancel_job) do
        {:ok, job}
      end
    end
  end

  def consume_cancel_package(%PackageCancelJob{patient_id_hash: patient_id_hash, user_id: user_id} = job) do
    with {:ok, data} <- decode_signed_data(job.signed_data),
         {:ok, %{"content" => content, "signer" => signer}} <- validate_signed_data(data),
         :ok <- JsonSchema.validate(:package_cancel_signed_content, content),
         :ok <- OneOf.validate(content, @one_of_request_params),
         employee_id <- get_in(content, ["encounter", "performer", "identifier", "value"]),
         encounter_id <- content["encounter"]["id"],
         :ok <- validate_signatures(signer, employee_id, user_id, job.client_id),
         {_, %{} = patient} <- {:patient, get_by_id(patient_id_hash)},
         {_, {:ok, %Encounter{} = encounter}} <- {:encounter, Encounters.get_by_id(patient_id_hash, encounter_id)},
         {_, {:ok, %Episode{} = episode}} <-
           {:episode, Episodes.get_by_id(patient_id_hash, to_string(encounter.episode.identifier.value))},
         :ok <- CancelEncounter.validate(content, episode, encounter, patient_id_hash, job.client_id),
         :ok <- CancelEncounter.save(patient, content, episode, encounter_id, job) do
      :ok
    else
      {:error, %{"error" => error, "meta" => _}} ->
        Jobs.produce_update_status(job._id, job.request_id, error, 422)

      {:patient, _} ->
        Jobs.produce_update_status(job._id, job.request_id, "Patient not found", 404)

      {:episode, _} ->
        Jobs.produce_update_status(job._id, job.request_id, "Encounter's episode not found", 404)

      {:encounter, _} ->
        Jobs.produce_update_status(job._id, job.request_id, "Encounter not found", 404)

      {:error, error} ->
        Jobs.produce_update_status(job._id, job.request_id, ValidationError.render("422.json", %{schema: error}), 422)

      {_, response, status_code} ->
        Jobs.produce_update_status(job._id, job.request_id, response, status_code)
    end
  end

  def consume_create_package(
        %PackageCreateJob{
          patient_id: patient_id,
          user_id: user_id
        } = job
      ) do
    with {:ok, data} <- decode_signed_data(job.signed_data),
         {:ok, %{"content" => content, "signer" => signer}} <- validate_signed_data(data),
         :ok <- JsonSchema.validate(:package_create_signed_content, content),
         :ok <- OneOf.validate(content, @one_of_request_params),
         employee_id <- get_in(content, ["encounter", "performer", "identifier", "value"]),
         :ok <- validate_signatures(signer, employee_id, user_id, job.client_id) do
      with {:ok, visit} <- create_visit(job),
           {:ok, observations} <- create_observations(job, content),
           {:ok, conditions} <- create_conditions(job, content, observations),
           {:ok, encounter} <- create_encounter(job, content, conditions, visit),
           {:ok, immunizations} <- create_immunizations(job, content, observations),
           {:ok, allergy_intolerances} <- create_allergy_intolerances(job, content),
           {:ok, diagnostic_reports} <- create_diagnostic_reports(job, content),
           {:ok, risk_assessments} <-
             create_risk_assessments(job, observations, conditions, diagnostic_reports, content),
           {:ok, devices} <- create_devices(job, content),
           {:ok, medication_statements} <- create_medication_statements(job, content) do
        encounter =
          encounter
          |> Encounters.fill_up_encounter_performer()
          |> Encounters.fill_up_diagnoses_codes()

        resource_name = "#{encounter.id}/create"
        files = [{'signed_content.txt', job.signed_data}]
        {:ok, {_, compressed_content}} = :zip.create("signed_content.zip", files, [:memory])

        with :ok <-
               @media_storage.save(
                 patient_id,
                 compressed_content,
                 Confex.fetch_env!(:core, Core.Microservices.MediaStorage)[:encounter_bucket],
                 resource_name
               ) do
          encounter = %{encounter | signed_content_links: [resource_name]}

          result =
            Package.save(
              job,
              %{
                "visit" => visit,
                "encounter" => encounter,
                "immunizations" => immunizations,
                "allergy_intolerances" => allergy_intolerances,
                "risk_assessments" => risk_assessments,
                "devices" => devices,
                "medication_statements" => medication_statements,
                "diagnostic_reports" => diagnostic_reports,
                "observations" => observations,
                "conditions" => conditions
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

  defp create_visit(%PackageCreateJob{visit: nil}), do: {:ok, nil}

  defp create_visit(%PackageCreateJob{
         patient_id_hash: patient_id_hash,
         user_id: user_id,
         visit: visit
       }) do
    now = DateTime.utc_now()
    visit = Visit.create(visit)

    visit =
      %{visit | inserted_by: user_id, updated_by: user_id, inserted_at: now, updated_at: now}
      |> VisitValidations.validate_period()

    case Vex.errors(%{visit: visit}, visit: [reference: [path: "visit"]]) do
      [] ->
        result =
          Patient.metadata().collection
          |> Mongo.aggregate([
            %{"$match" => %{"_id" => patient_id_hash}},
            %{"$project" => %{"_id" => "$visits.#{visit.id}.id"}}
          ])
          |> Enum.to_list()

        case result do
          [%{"_id" => _}] ->
            {:error, "Visit with such id already exists", 409}

          _ ->
            {:ok, visit}
        end

      errors ->
        {:error, errors}
    end
  end

  defp create_encounter(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         content,
         conditions,
         visit
       ) do
    now = DateTime.utc_now()
    encounter = Encounter.create(content["encounter"])

    encounter =
      %{
        encounter
        | inserted_by: user_id,
          updated_by: user_id,
          inserted_at: now,
          updated_at: now
      }
      |> EncounterValidations.validate_episode(client_id, patient_id_hash)
      |> EncounterValidations.validate_visit(visit, patient_id_hash)
      |> EncounterValidations.validate_performer(client_id)
      |> EncounterValidations.validate_division(client_id)
      |> EncounterValidations.validate_diagnoses(conditions, encounter.class, patient_id_hash)
      |> EncounterValidations.validate_date()
      |> EncounterValidations.validate_incoming_referrals(client_id)
      |> EncounterValidations.validate_supporting_info(patient_id_hash)

    case Vex.errors(%{encounter: encounter}, encounter: [reference: [path: "encounter"]]) do
      [] ->
        result =
          Patient.metadata().collection
          |> Mongo.aggregate([
            %{"$match" => %{"_id" => patient_id_hash}},
            %{"$project" => %{"_id" => "$encounters.#{encounter.id}.id"}}
          ])
          |> Enum.to_list()

        case result do
          [%{"_id" => _}] ->
            {:error, "Encounter with such id already exists", 409}

          _ ->
            {:ok, encounter}
        end

      errors ->
        {:error, errors}
    end
  end

  defp create_conditions(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"conditions" => _} = content,
         observations
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    conditions =
      Enum.map(content["conditions"], fn data ->
        condition = Condition.create(data)

        %{
          condition
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id,
            patient_id: patient_id_hash
        }
        |> ConditionValidations.validate_onset_date()
        |> ConditionValidations.validate_context(encounter_id)
        |> ConditionValidations.validate_evidences(observations, patient_id_hash)
        |> ConditionValidations.validate_source(client_id)
      end)

    case Vex.errors(
           %{conditions: conditions},
           conditions: [unique_ids: [field: :_id], reference: [path: "conditions"]]
         ) do
      [] ->
        validate_conditions(conditions)

      errors ->
        {:error, errors}
    end
  end

  defp create_conditions(_, _, _), do: {:ok, []}

  defp create_observations(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"observations" => _} = content
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

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
        |> ObservationValidations.validate_context(encounter_id)
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

  defp create_immunizations(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         content,
         observations
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]
    immunization_observation_id_map = get_immunization_observation_id_map(content)
    db_immunization_ids = get_db_immunization_ids(content)

    immunizations =
      Enum.map(content["immunizations"] || [], fn data ->
        immunization =
          data
          |> create_immunization_reactions(immunization_observation_id_map)
          |> Immunization.create()

        %{
          immunization
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id
        }
        |> ImmunizationValidations.validate_date()
        |> ImmunizationValidations.validate_context(encounter_id)
        |> ImmunizationValidations.validate_source(client_id)
        |> ImmunizationValidations.validate_reactions(observations, patient_id_hash)
      end)

    with {:ok, db_immunizations} <- get_db_immunizations(db_immunization_ids, patient_id_hash) do
      immunizations =
        immunizations ++ update_db_immunizations(db_immunizations, user_id, immunization_observation_id_map)

      case Vex.errors(
             %{immunizations: immunizations},
             immunizations: [unique_ids: [field: :id], reference: [path: "immunizations"]]
           ) do
        [] ->
          validate_immunizations(patient_id_hash, immunizations)

        errors ->
          {:error, errors}
      end
    end
  end

  defp get_db_immunizations(immunization_ids, patient_id_hash) do
    with {:ok, immunizations} <- Immunizations.get_by_ids(patient_id_hash, immunization_ids) do
      {:ok, immunizations}
    else
      {:error, message} -> {:error, %{"error" => message}, 404}
    end
  end

  defp update_db_immunizations(immunizations, user_id, immunization_observation_id_map) do
    now = DateTime.utc_now()

    Enum.map(immunizations, fn %{id: immunization_id} = immunization ->
      previous_reactions = immunization.reactions || []

      new_reactions =
        immunization_observation_id_map
        |> Map.get(to_string(immunization_id), [])
        |> Enum.map(&Reaction.create(create_reaction(&1)))

      reactions =
        previous_reactions
        |> Enum.concat(new_reactions)
        |> case do
          [] -> nil
          reactions -> reactions
        end

      %{immunization | reactions: reactions, updated_at: now, updated_by: user_id}
    end)
  end

  defp get_immunization_observation_id_map(content) do
    content
    |> Map.get("observations", [])
    |> Enum.reduce(%{}, fn %{"id" => observation_id} = observation, acc ->
      case get_reaction_on_immunization_id(observation["reaction_on"]) do
        nil -> acc
        immunization_id -> Map.merge(acc, %{immunization_id => [observation_id]}, fn _key, v1, v2 -> [v2 | v1] end)
      end
    end)
  end

  defp get_request_immunization_ids(content) do
    content
    |> Map.get("immunizations", [])
    |> Enum.map(& &1["id"])
  end

  defp get_reactions_immunization_ids(content) do
    content
    |> Map.get("observations", [])
    |> Enum.map(&get_reaction_on_immunization_id(&1["reaction_on"]))
    |> Enum.reject(&is_nil/1)
  end

  defp get_db_immunization_ids(content) do
    immunization_ids_from_request = get_request_immunization_ids(content)
    immunization_ids_from_reactions_on = get_reactions_immunization_ids(content)

    immunization_ids_from_reactions_on -- immunization_ids_from_request
  end

  defp get_reaction_on_immunization_id(%{"identifier" => %{"value" => immunization_id}}), do: immunization_id
  defp get_reaction_on_immunization_id(_), do: nil

  defp create_immunization_reactions(%{"id" => immunization_id} = data, immunization_observation_id_map) do
    case immunization_observation_id_map[immunization_id] do
      nil -> data
      observation_ids -> Map.put(data, "reactions", Enum.map(observation_ids, &create_reaction(&1)))
    end
  end

  defp create_reaction(observation_id) do
    %{
      "detail" => %{
        "identifier" => %{
          "type" => %{
            "coding" => [
              %{
                "system" => "eHealth/resources",
                "code" => "observation"
              }
            ]
          },
          "value" => observation_id
        }
      }
    }
  end

  defp create_allergy_intolerances(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"allergy_intolerances" => _} = content
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    allergy_intolerances =
      Enum.map(content["allergy_intolerances"], fn data ->
        allergy_intolerance = AllergyIntolerance.create(data)

        %{
          allergy_intolerance
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id
        }
        |> AllergyIntoleranceValidations.validate_context(encounter_id)
        |> AllergyIntoleranceValidations.validate_source(client_id)
        |> AllergyIntoleranceValidations.validate_onset_date_time()
        |> AllergyIntoleranceValidations.validate_last_occurrence()
        |> AllergyIntoleranceValidations.validate_asserted_date()
      end)

    case Vex.errors(
           %{allergy_intolerances: allergy_intolerances},
           allergy_intolerances: [
             unique_ids: [field: :id],
             reference: [path: "allergy_intolerances"]
           ]
         ) do
      [] ->
        validate_allergy_intolerances(patient_id_hash, allergy_intolerances)

      errors ->
        {:error, errors}
    end
  end

  defp create_allergy_intolerances(_, _), do: {:ok, []}

  defp create_risk_assessments(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         observations,
         conditions,
         diagnostic_reports,
         %{"risk_assessments" => _} = content
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    risk_assessments =
      Enum.map(content["risk_assessments"], fn data ->
        risk_assessment = RiskAssessment.create(data)

        %{
          risk_assessment
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id
        }
        |> RiskAssessmentValidations.validate_context(encounter_id)
        |> RiskAssessmentValidations.validate_asserted_date()
        |> RiskAssessmentValidations.validate_reason_references(
          observations,
          conditions,
          diagnostic_reports,
          patient_id_hash
        )
        |> RiskAssessmentValidations.validate_basis_references(
          observations,
          conditions,
          diagnostic_reports,
          patient_id_hash
        )
        |> RiskAssessmentValidations.validate_performer(client_id)
        |> RiskAssessmentValidations.validate_predictions()
      end)

    case Vex.errors(
           %{risk_assessments: risk_assessments},
           risk_assessments: [
             unique_ids: [field: :id],
             reference: [path: "risk_assessments"]
           ]
         ) do
      [] ->
        validate_risk_assessments(patient_id_hash, risk_assessments)

      errors ->
        {:error, errors}
    end
  end

  defp create_risk_assessments(_, _, _, _, _), do: {:ok, []}

  defp create_devices(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"devices" => _} = content
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    devices =
      Enum.map(content["devices"], fn data ->
        device = Device.create(data)

        %{
          device
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id
        }
        |> DeviceValidations.validate_context(encounter_id)
        |> DeviceValidations.validate_asserted_date()
        |> DeviceValidations.validate_source(client_id)
        |> DeviceValidations.validate_usage_period()
      end)

    case Vex.errors(
           %{devices: devices},
           devices: [
             unique_ids: [field: :id],
             reference: [path: "devices"]
           ]
         ) do
      [] ->
        validate_devices(patient_id_hash, devices)

      errors ->
        {:error, errors}
    end
  end

  defp create_devices(_, _), do: {:ok, []}

  defp create_medication_statements(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"medication_statements" => _} = content
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    medication_statements =
      Enum.map(content["medication_statements"], fn data ->
        medication_statement = MedicationStatement.create(data)

        %{
          medication_statement
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id
        }
        |> MedicationStatementValidations.validate_context(encounter_id)
        |> MedicationStatementValidations.validate_asserted_date()
        |> MedicationStatementValidations.validate_source(client_id)
        |> MedicationStatementValidations.validate_based_on(patient_id_hash)
      end)

    case Vex.errors(
           %{medication_statements: medication_statements},
           medication_statements: [
             unique_ids: [field: :id],
             reference: [path: "medication_statements"]
           ]
         ) do
      [] ->
        validate_medication_statements(patient_id_hash, medication_statements)

      errors ->
        {:error, errors}
    end
  end

  defp create_medication_statements(_, _), do: {:ok, []}

  defp create_diagnostic_reports(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"diagnostic_reports" => _} = content
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    diagnostic_reports =
      Enum.map(content["diagnostic_reports"], fn data ->
        diagnostic_report = DiagnosticReport.create(data)

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
        |> DiagnosticReportValidations.validate_encounter(encounter_id)
        |> DiagnosticReportValidations.validate_source(client_id)
        |> DiagnosticReportValidations.validate_managing_organization(client_id)
        |> DiagnosticReportValidations.validate_results_interpreter(client_id)
      end)

    case Vex.errors(
           %{diagnostic_reports: diagnostic_reports},
           diagnostic_reports: [
             unique_ids: [field: :id],
             reference: [path: "diagnostic_reports"]
           ]
         ) do
      [] ->
        validate_diagnostic_reports(patient_id_hash, diagnostic_reports)

      errors ->
        {:error, errors}
    end
  end

  defp create_diagnostic_reports(_, _), do: {:ok, []}

  defp validate_conditions(conditions) do
    Enum.reduce_while(conditions, {:ok, conditions}, fn condition, acc ->
      if Mongo.find_one(
           Condition.metadata().collection,
           %{"_id" => Mongo.string_to_uuid(condition._id)},
           projection: %{"_id" => true}
         ) do
        {:halt, {:error, "Condition with id '#{condition._id}' already exists", 409}}
      else
        {:cont, acc}
      end
    end)
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

  defp validate_immunizations(patient_id_hash, immunizations) do
    Enum.reduce_while(immunizations, {:ok, immunizations}, fn immunization, acc ->
      case Immunizations.get_by_id(patient_id_hash, immunization.id) do
        {:ok, _} ->
          {:halt, {:error, "Immunization with id '#{immunization.id}' already exists", 409}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp validate_allergy_intolerances(patient_id_hash, allergy_intolerances) do
    Enum.reduce_while(allergy_intolerances, {:ok, allergy_intolerances}, fn allergy_intolerance, acc ->
      case AllergyIntolerances.get_by_id(patient_id_hash, allergy_intolerance.id) do
        {:ok, _} ->
          {:halt, {:error, "Allergy intolerance with id '#{allergy_intolerance.id}' already exists", 409}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp validate_risk_assessments(patient_id_hash, risk_assessments) do
    Enum.reduce_while(risk_assessments, {:ok, risk_assessments}, fn risk_assessment, acc ->
      case RiskAssessments.get_by_id(patient_id_hash, risk_assessment.id) do
        {:ok, _} ->
          {:halt, {:error, "Risk assessment with id '#{risk_assessment.id}' already exists", 409}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp validate_devices(patient_id_hash, devices) do
    Enum.reduce_while(devices, {:ok, devices}, fn device, acc ->
      case Devices.get_by_id(patient_id_hash, device.id) do
        {:ok, _} ->
          {:halt, {:error, "Device with id '#{device.id}' already exists", 409}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp validate_medication_statements(patient_id_hash, medication_statements) do
    Enum.reduce_while(medication_statements, {:ok, medication_statements}, fn medication_statement, acc ->
      case MedicationStatements.get_by_id(patient_id_hash, medication_statement.id) do
        {:ok, _} ->
          {:halt, {:error, "Medication statement with id '#{medication_statement.id}' already exists", 409}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp validate_diagnostic_reports(patient_id_hash, diagnostic_reports) do
    Enum.reduce_while(diagnostic_reports, {:ok, diagnostic_reports}, fn diagnostic_report, acc ->
      case DiagnosticReports.get_by_id(patient_id_hash, diagnostic_report.id) do
        {:ok, _} ->
          {:halt, {:error, "Diagnostic report with id '#{diagnostic_report.id}' already exists", 409}}

        _ ->
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
