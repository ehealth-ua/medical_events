defmodule Core.Patients.Encounters.Cancel do
  @moduledoc false

  alias Core.AllergyIntolerance
  alias Core.Condition
  alias Core.Conditions
  alias Core.DateView
  alias Core.Device
  alias Core.DiagnosisView
  alias Core.DiagnosticReport
  alias Core.Encounter
  alias Core.Episode
  alias Core.Immunization
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.PackageCancelJob
  alias Core.MedicationStatement
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.Observation
  alias Core.Observations
  alias Core.Patient
  alias Core.Patients.AllergyIntolerances
  alias Core.Patients.Devices
  alias Core.Patients.DiagnosticReports
  alias Core.Patients.Episodes.Validations, as: EpisodeValidations
  alias Core.Patients.Immunizations
  alias Core.Patients.MedicationStatements
  alias Core.Patients.RiskAssessments
  alias Core.ReferenceView
  alias Core.RiskAssessment
  alias Core.UUIDView
  alias Core.Validators.Vex
  alias EView.Views.ValidationError

  require Logger

  @media_storage Application.get_env(:core, :microservices)[:media_storage]

  @patients_collection Patient.metadata().collection
  @observations_collection Observation.metadata().collection
  @conditions_collection Condition.metadata().collection

  @entered_in_error "entered_in_error"

  @entities_meta %{
    "allergy_intolerances" => [status: "verification_status"],
    "risk_assessments" => [status: "status"],
    "immunizations" => [status: "status"],
    "conditions" => [status: "verification_status"],
    "observations" => [status: "status"],
    "devices" => [status: "status"],
    "medication_statements" => [status: "status"],
    "diagnostic_reports" => [status: "status"]
  }

  @doc """
  Performs validation by comparing encounter packages which created retrieved from job signed data and database
  Package entities except `encounter` are MapSet's to ignore position in list
  """
  def validate(decoded_content, %Episode{} = episode, %Encounter{} = encounter, patient_id_hash, client_id) do
    encounter_request_package = create_encounter_package_from_request(decoded_content)

    with :ok <- validate_episode_managing_organization(episode, client_id),
         :ok <- validate_has_entity_entered_in_error(decoded_content),
         {:ok, encounter_package} <- create_encounter_package(encounter, patient_id_hash, decoded_content),
         :ok <- validate_enounter_packages(encounter_package, encounter_request_package),
         :ok <- validate_conditions(decoded_content) do
      :ok
    end
  end

  def save(
        patient,
        package_data,
        %Episode{} = episode,
        encounter_id,
        %PackageCancelJob{patient_id: patient_id, user_id: user_id} = job
      ) do
    conditions_ids = get_conditions_ids(package_data)
    observations_ids = get_observations_ids(package_data)

    update_data = %{
      allergy_intolerances_ids: get_allergy_intolerances_ids(package_data),
      risk_assessments_ids: get_risk_assessments_ids(package_data),
      immunizations_ids: get_immunizations_ids(package_data),
      devices_ids: get_devices_ids(package_data),
      medication_statements_ids: get_medication_statements_ids(package_data),
      diagnostic_reports_ids: get_diagnostic_reports_ids(package_data),
      current_diagnoses: get_current_diagnoses(episode, encounter_id)
    }

    with :ok <- save_signed_content(patient_id, encounter_id, job.signed_data),
         set <-
           update_patient(
             user_id,
             patient,
             package_data,
             update_data
           ) do
      result =
        %Transaction{}
        |> Transaction.add_operation(@patients_collection, :update, %{"_id" => job.patient_id_hash}, %{"$set" => set})
        |> update_conditions(conditions_ids, user_id)
        |> update_observations(observations_ids, user_id)
        |> Jobs.update(job._id, Job.status(:processed), %{}, 200)
        |> Transaction.flush()

      case result do
        :ok -> :ok
        {:error, reason} -> {:error, reason, 500}
      end
    end
  end

  defp update_conditions(%Transaction{} = transaction, ids, user_id) do
    Enum.reduce(ids, transaction, fn id, acc ->
      Transaction.add_operation(acc, @conditions_collection, :update, %{"_id" => Mongo.string_to_uuid(id)}, %{
        "$set" => %{
          "verification_status" => @entered_in_error,
          "updated_by" => Mongo.string_to_uuid(user_id),
          "updated_at" => DateTime.utc_now()
        }
      })
    end)
  end

  defp update_observations(%Transaction{} = transaction, ids, user_id) do
    Enum.reduce(ids, transaction, fn id, acc ->
      Transaction.add_operation(acc, @observations_collection, :update, %{"_id" => Mongo.string_to_uuid(id)}, %{
        "$set" => %{
          "status" => @entered_in_error,
          "updated_by" => Mongo.string_to_uuid(user_id),
          "updated_at" => DateTime.utc_now()
        }
      })
    end)
  end

  defp save_signed_content(patient_id, encounter_id, signed_data) do
    resource_name = "#{encounter_id}/cancel"
    files = [{'signed_content.txt', signed_data}]
    {:ok, {_, compressed_content}} = :zip.create("signed_content.zip", files, [:memory])

    @media_storage.save(
      patient_id,
      compressed_content,
      Confex.fetch_env!(:core, Core.Microservices.MediaStorage)[:encounter_bucket],
      resource_name
    )
  end

  defp get_allergy_intolerances_ids(package_data) do
    package_data
    |> Map.get("allergy_intolerances", [])
    |> Enum.filter(&(Map.get(&1, "verification_status") == @entered_in_error))
    |> Enum.map(&Map.get(&1, "id"))
  end

  defp get_risk_assessments_ids(package_data) do
    package_data
    |> Map.get("risk_assessments", [])
    |> Enum.filter(&(Map.get(&1, "status") == @entered_in_error))
    |> Enum.map(&Map.get(&1, "id"))
  end

  defp get_immunizations_ids(package_data) do
    package_data
    |> Map.get("immunizations", [])
    |> Enum.filter(&(Map.get(&1, "status") == @entered_in_error))
    |> Enum.map(&Map.get(&1, "id"))
  end

  defp get_conditions_ids(package_data) do
    package_data
    |> Map.get("conditions", [])
    |> Enum.filter(&(Map.get(&1, "verification_status") == @entered_in_error))
    |> Enum.map(&Map.get(&1, "id"))
  end

  defp get_observations_ids(package_data) do
    package_data
    |> Map.get("observations", [])
    |> Enum.filter(&(Map.get(&1, "status") == @entered_in_error))
    |> Enum.map(&Map.get(&1, "id"))
  end

  defp get_devices_ids(package_data) do
    package_data
    |> Map.get("devices", [])
    |> Enum.filter(&(Map.get(&1, "status") == @entered_in_error))
    |> Enum.map(&Map.get(&1, "id"))
  end

  defp get_medication_statements_ids(package_data) do
    package_data
    |> Map.get("medication_statements", [])
    |> Enum.filter(&(Map.get(&1, "status") == @entered_in_error))
    |> Enum.map(&Map.get(&1, "id"))
  end

  defp get_diagnostic_reports_ids(package_data) do
    package_data
    |> Map.get("diagnostic_reports", [])
    |> Enum.filter(&(Map.get(&1, "status") == @entered_in_error))
    |> Enum.map(&Map.get(&1, "id"))
  end

  defp update_patient(
         user_id,
         patient,
         %{"encounter" => encounter},
         update_data
       ) do
    now = DateTime.utc_now()

    %{"updated_by" => user_id, "updated_at" => now}
    |> Mongo.convert_to_uuid("updated_by")
    |> Mongo.add_to_set(
      update_data.current_diagnoses,
      "episodes.#{get_in(encounter, ~w(episode identifier value))}.current_diagnoses"
    )
    |> set_allergy_intolerances(update_data.allergy_intolerances_ids, user_id, now)
    |> set_risk_assessments(update_data.risk_assessments_ids, user_id, now)
    |> set_immunizations(update_data.immunizations_ids, user_id, now)
    |> set_devices(update_data.devices_ids, user_id, now)
    |> set_medication_statements(update_data.medication_statements_ids, user_id, now)
    |> set_diagnostic_reports(update_data.diagnostic_reports_ids, user_id, now)
    |> set_encounter(user_id, encounter, now)
    |> set_encounter_diagnoses(patient, encounter)
  end

  defp set_allergy_intolerances(set, ids, user_id, now) do
    Enum.reduce(ids, set, fn id, acc ->
      acc
      |> Mongo.add_to_set(@entered_in_error, "allergy_intolerances.#{id}.verification_status")
      |> Mongo.add_to_set(user_id, "allergy_intolerances.#{id}.updated_by")
      |> Mongo.add_to_set(now, "allergy_intolerances.#{id}.updated_at")
      |> Mongo.convert_to_uuid("allergy_intolerances.#{id}.updated_by")
    end)
  end

  defp set_risk_assessments(set, ids, user_id, now) do
    Enum.reduce(ids, set, fn id, acc ->
      acc
      |> Mongo.add_to_set(@entered_in_error, "risk_assessments.#{id}.status")
      |> Mongo.add_to_set(user_id, "risk_assessments.#{id}.updated_by")
      |> Mongo.add_to_set(now, "risk_assessments.#{id}.updated_at")
      |> Mongo.convert_to_uuid("risk_assessments.#{id}.updated_by")
    end)
  end

  defp set_immunizations(set, ids, user_id, now) do
    Enum.reduce(ids, set, fn id, acc ->
      acc
      |> Mongo.add_to_set(@entered_in_error, "immunizations.#{id}.status")
      |> Mongo.add_to_set(user_id, "immunizations.#{id}.updated_by")
      |> Mongo.add_to_set(now, "immunizations.#{id}.updated_at")
      |> Mongo.convert_to_uuid("immunizations.#{id}.updated_by")
    end)
  end

  defp set_devices(set, ids, user_id, now) do
    Enum.reduce(ids, set, fn id, acc ->
      acc
      |> Mongo.add_to_set(@entered_in_error, "devices.#{id}.status")
      |> Mongo.add_to_set(user_id, "devices.#{id}.updated_by")
      |> Mongo.add_to_set(now, "devices.#{id}.updated_at")
      |> Mongo.convert_to_uuid("devices.#{id}.updated_by")
    end)
  end

  defp set_medication_statements(set, ids, user_id, now) do
    Enum.reduce(ids, set, fn id, acc ->
      acc
      |> Mongo.add_to_set(@entered_in_error, "medication_statements.#{id}.status")
      |> Mongo.add_to_set(user_id, "medication_statements.#{id}.updated_by")
      |> Mongo.add_to_set(now, "medication_statements.#{id}.updated_at")
      |> Mongo.convert_to_uuid("medication_statements.#{id}.updated_by")
    end)
  end

  defp set_diagnostic_reports(set, ids, user_id, now) do
    Enum.reduce(ids, set, fn id, acc ->
      acc
      |> Mongo.add_to_set(@entered_in_error, "diagnostic_reports.#{id}.status")
      |> Mongo.add_to_set(user_id, "diagnostic_reports.#{id}.updated_by")
      |> Mongo.add_to_set(now, "diagnostic_reports.#{id}.updated_at")
      |> Mongo.convert_to_uuid("diagnostic_reports.#{id}.updated_by")
    end)
  end

  defp set_encounter(set, user_id, %{"id" => encounter_id} = encounter, now) do
    # TODO: divisions history logic is not specified yet
    set
    |> Mongo.add_to_set(user_id, "encounters.#{encounter_id}.updated_by")
    |> Mongo.add_to_set(now, "encounters.#{encounter_id}.updated_at")
    |> Mongo.add_to_set(
      encounter["cancellation_reason"],
      "encounters.#{encounter_id}.cancellation_reason"
    )
    |> Mongo.add_to_set(
      encounter["explanatory_letter"],
      "encounters.#{encounter_id}.explanatory_letter"
    )
    |> Mongo.convert_to_uuid("encounters.#{encounter_id}.updated_by")
    |> set_encounter_status(encounter)
  end

  defp set_encounter_status(set, %{"id" => id, "status" => @entered_in_error}) do
    Mongo.add_to_set(set, @entered_in_error, "encounters.#{id}.status")
  end

  defp set_encounter_status(set, _), do: set

  defp set_encounter_diagnoses(set, patient, %{"id" => encounter_id, "status" => @entered_in_error}) do
    encounter_uuid = Mongo.string_to_uuid(encounter_id)
    episode_id = to_string(patient["encounters"][encounter_id]["episode"]["identifier"]["value"])

    diagnoses_history = patient["episodes"][episode_id]["diagnoses_history"]

    diagnoses_history
    |> Enum.with_index()
    |> Enum.reduce(set, fn {diagnos_history, index}, set ->
      if diagnos_history["is_active"] and diagnos_history["evidence"]["identifier"]["value"] == encounter_uuid do
        Mongo.add_to_set(set, false, "episodes.#{episode_id}.diagnoses_history.#{index}.is_active")
      else
        set
      end
    end)
  end

  defp set_encounter_diagnoses(set, _patient, _encounter), do: set

  defp get_entities_to_load(decoded_content) do
    available_entities = Map.keys(@entities_meta)

    decoded_content
    |> Map.delete("encounter")
    |> Map.keys()
    |> Enum.filter(&(&1 in available_entities))
  end

  defp create_encounter_package(%Encounter{id: encounter_uuid} = encounter, patient_id_hash, decoded_content) do
    package =
      decoded_content
      |> filter_entities_to_compare()
      |> Enum.reduce(%{}, fn {entity_key, entity_ids}, acc ->
        entity_key_atom = String.to_atom(entity_key)
        entities = get_entities(entity_key, entity_ids, patient_id_hash, encounter_uuid)

        Map.put(acc, entity_key_atom, entities)
      end)
      |> Map.put(:encounter, encounter)

    with :ok <- validate_package_has_no_entered_in_error_entities(package) do
      {:ok, render_package_entities(package)}
    end
  end

  defp validate_has_entity_entered_in_error(%{"encounter" => encounter} = decoded_content) do
    [
      [encounter["status"]],
      get_entities_statuses(decoded_content["allergy_intolerances"], "verification_status"),
      get_entities_statuses(decoded_content["risk_assessments"], "status"),
      get_entities_statuses(decoded_content["immunizations"], "status"),
      get_entities_statuses(decoded_content["conditions"], "verification_status"),
      get_entities_statuses(decoded_content["observations"], "status"),
      get_entities_statuses(decoded_content["devices"], "status"),
      get_entities_statuses(decoded_content["medication_statements"], "status"),
      get_entities_statuses(decoded_content["diagnostic_reports"], "status")
    ]
    |> Enum.flat_map(& &1)
    |> Enum.any?(&(&1 == @entered_in_error))
    |> case do
      true -> :ok
      _ -> {:ok, %{"error" => ~s(At least one entity should have status "entered_in_error")}, 409}
    end
  end

  defp get_entities_statuses(nil, _status_field), do: []
  defp get_entities_statuses(entities, status_field), do: Enum.map(entities, &Map.get(&1, status_field))

  defp validate_package_has_no_entered_in_error_entities(%{encounter: encounter} = package) do
    [
      encounter: [encounter.status],
      allergy_intolerance: get_entities_statuses(package[:allergy_intolerances], :verification_status),
      risk_assessment: get_entities_statuses(package[:risk_assessments], :status),
      immunization: get_entities_statuses(package[:immunizations], :status),
      condition: get_entities_statuses(package[:conditions], :verification_status),
      observation: get_entities_statuses(package[:observations], :status),
      device: get_entities_statuses(package[:devices], :status),
      medication_statement: get_entities_statuses(package[:medication_statements], :status),
      diagnostic_reports: get_entities_statuses(package[:diagnostic_reports], :status)
    ]
    |> Enum.reject(fn {_, statuses} -> statuses == [] end)
    |> Enum.reduce_while(:ok, fn {key, statuses}, _acc ->
      case @entered_in_error in statuses do
        true -> {:halt, {:ok, %{"error" => "Invalid transition for #{key} - already entered_in_error"}, 409}}
        _ -> {:cont, :ok}
      end
    end)
  end

  defp render_package_entities(package) do
    package
    |> Enum.map(fn
      {:encounter = key, entity} -> {key, render(key, entity)}
      {key, entities} -> {key, MapSet.new(render(key, entities))}
    end)
    |> Enum.into(%{})
  end

  defp create_encounter_package_from_request(decoded_content) do
    entities_to_load = get_entities_to_load(decoded_content)

    entity_creators = %{
      "conditions" => &Condition.create/1,
      "allergy_intolerances" => &AllergyIntolerance.create/1,
      "risk_assessments" => &RiskAssessment.create/1,
      "immunizations" => &Immunization.create/1,
      "observations" => &Observation.create/1,
      "devices" => &Device.create/1,
      "medication_statements" => &MedicationStatement.create/1,
      "diagnostic_reports" => &DiagnosticReport.create/1
    }

    entities_to_load
    |> Enum.reduce(%{}, fn entity_key, acc ->
      entities = Enum.map(decoded_content[entity_key], &entity_creators[entity_key].(&1))

      Map.put(acc, String.to_atom(entity_key), entities)
    end)
    |> Map.put(:encounter, Encounter.create(decoded_content["encounter"]))
    |> render_package_entities()
  end

  defp filter_entities_to_compare(package_data) do
    @entities_meta
    |> Map.keys()
    |> Enum.map(fn entity_key ->
      entities_ids = Enum.map(package_data[entity_key] || [], & &1["id"])
      {entity_key, entities_ids}
    end)
    |> Enum.reject(fn {_key, entities} -> entities == [] end)
  end

  defp validate_enounter_packages(package, request_package) do
    package = Iteraptor.to_flatmap(package)
    request_package = Iteraptor.to_flatmap(request_package)

    request_package
    |> Enum.reject(fn {key, value} -> package[key] == value end)
    |> case do
      [] ->
        :ok

      [{error_path, _} | _] ->
        {:ok,
         %{
           "error" => "Submitted signed content does not correspond to previously created content: #{error_path}"
         }, 409}
    end
  end

  defp validate_conditions(%{"encounter" => %{"status" => @entered_in_error}}), do: :ok

  defp validate_conditions(%{
         "encounter" => %{"diagnoses" => diagnoses},
         "conditions" => conditions
       })
       when is_list(diagnoses) and is_list(conditions) do
    conditions_id =
      conditions
      |> Enum.filter(&(&1["verification_status"] == "entered_in_error"))
      |> Enum.map(& &1["id"])
      |> MapSet.new()

    diagnoses_conditions_id =
      diagnoses
      |> Enum.map(& &1["condition"]["identifier"]["value"])
      |> MapSet.new()

    conditions_id
    |> MapSet.intersection(diagnoses_conditions_id)
    |> MapSet.size()
    |> Kernel.!=(0)
    |> case do
      true ->
        {:ok, %{"error" => "The condition can not be canceled while encounter is not canceled"}, 409}

      _ ->
        :ok
    end
  end

  defp validate_conditions(_), do: :ok

  defp validate_episode_managing_organization(%Episode{} = episode, client_id) do
    managing_organization = episode.managing_organization
    identifier = managing_organization.identifier

    episode =
      %{
        episode
        | managing_organization: %{
            managing_organization
            | identifier: %{identifier | value: UUID.binary_to_string!(identifier.value.binary)}
          }
      }
      |> EpisodeValidations.validate_managing_organization(client_id)

    case Vex.errors(episode) do
      [] ->
        :ok

      errors ->
        {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}), 422}
    end
  end

  defp get_entities("allergy_intolerances", ids, patient_id_hash, encounter_uuid) do
    patient_id_hash
    |> AllergyIntolerances.get_by_encounter_id(encounter_uuid)
    |> Enum.filter(&(UUID.binary_to_string!(&1.id.binary) in ids))
  end

  defp get_entities("risk_assessments", ids, patient_id_hash, encounter_uuid) do
    patient_id_hash
    |> RiskAssessments.get_by_encounter_id(encounter_uuid)
    |> Enum.filter(&(UUID.binary_to_string!(&1.id.binary) in ids))
  end

  defp get_entities("immunizations", ids, patient_id_hash, encounter_uuid) do
    patient_id_hash
    |> Immunizations.get_by_encounter_id(encounter_uuid)
    |> Enum.filter(&(UUID.binary_to_string!(&1.id.binary) in ids))
  end

  defp get_entities("conditions", ids, patient_id_hash, encounter_uuid) do
    patient_id_hash
    |> Conditions.get_by_encounter_id(encounter_uuid)
    |> Enum.filter(&(UUID.binary_to_string!(&1._id.binary) in ids))
  end

  defp get_entities("observations", ids, patient_id_hash, encounter_uuid) do
    patient_id_hash
    |> Observations.get_by_encounter_id(encounter_uuid)
    |> Enum.filter(&(UUID.binary_to_string!(&1._id.binary) in ids))
  end

  defp get_entities("devices", ids, patient_id_hash, encounter_uuid) do
    patient_id_hash
    |> Devices.get_by_encounter_id(encounter_uuid)
    |> Enum.filter(&(UUID.binary_to_string!(&1.id.binary) in ids))
  end

  defp get_entities("medication_statements", ids, patient_id_hash, encounter_uuid) do
    patient_id_hash
    |> MedicationStatements.get_by_encounter_id(encounter_uuid)
    |> Enum.filter(&(UUID.binary_to_string!(&1.id.binary) in ids))
  end

  defp get_entities("diagnostic_reports", ids, patient_id_hash, encounter_uuid) do
    patient_id_hash
    |> DiagnosticReports.get_by_encounter_id(encounter_uuid)
    |> Enum.filter(&(UUID.binary_to_string!(&1.id.binary) in ids))
  end

  defp get_current_diagnoses(%Episode{diagnoses_history: diagnoses_history}, encounter_id) do
    current_diagnoses =
      diagnoses_history
      |> Enum.filter(fn history_item ->
        history_item.is_active && to_string(history_item.evidence.identifier.value) != encounter_id
      end)

    case current_diagnoses do
      [] -> []
      _ -> current_diagnoses |> List.last() |> Map.get(:diagnoses)
    end
  end

  defp render(:encounter, encounter) do
    %{
      id: UUIDView.render(encounter.id),
      date: DateView.render_datetime(encounter.date),
      visit: ReferenceView.render(encounter.visit),
      episode: render(encounter.episode),
      class: ReferenceView.render(encounter.class),
      type: ReferenceView.render(encounter.type),
      incoming_referrals: ReferenceView.render(encounter.incoming_referrals),
      performer: render(encounter.performer),
      reasons: ReferenceView.render(encounter.reasons),
      diagnoses: Enum.map(encounter.diagnoses, &DiagnosisView.render/1),
      actions: ReferenceView.render(encounter.actions),
      division: render(encounter.division),
      supporting_info: Enum.map(encounter.supporting_info, &render/1)
    }
  end

  defp render(:allergy_intolerances, allergy_intolerances) do
    Enum.map(allergy_intolerances, fn allergy_intolerance ->
      allergy_intolerance
      |> Map.take(~w(type category criticality primary_source)a)
      |> Map.merge(%{
        id: UUIDView.render(allergy_intolerance.id),
        context: ReferenceView.render(allergy_intolerance.context),
        code: ReferenceView.render(allergy_intolerance.code),
        onset_date_time: DateView.render_datetime(allergy_intolerance.onset_date_time),
        asserted_date: DateView.render_datetime(allergy_intolerance.asserted_date),
        last_occurrence: DateView.render_datetime(allergy_intolerance.last_occurrence)
      })
      |> Map.merge(render_source(allergy_intolerance.source))
    end)
  end

  defp render(:immunizations, immunizations) do
    Enum.map(immunizations, fn immunization ->
      immunization
      |> Map.take(~w(
        not_given
        primary_source
        manufacturer
        lot_number
      )a)
      |> Map.merge(%{
        id: UUIDView.render(immunization.id),
        vaccine_code: ReferenceView.render(immunization.vaccine_code),
        context: ReferenceView.render(immunization.context),
        date: DateView.render_datetime(immunization.date),
        legal_entity: ReferenceView.render(immunization.legal_entity),
        expiration_date: DateView.render_datetime(immunization.expiration_date),
        site: ReferenceView.render(immunization.site),
        route: ReferenceView.render(immunization.route),
        dose_quantity: ReferenceView.render(immunization.dose_quantity),
        vaccination_protocols: ReferenceView.render(immunization.vaccination_protocols),
        explanation: ReferenceView.render(immunization.explanation)
      })
      |> Map.merge(render_source(immunization.source))
    end)
  end

  defp render(:conditions, conditions) do
    Enum.map(conditions, fn condition ->
      %{
        id: UUIDView.render(condition._id),
        primary_source: condition.primary_source,
        context: ReferenceView.render(condition.context),
        code: ReferenceView.render(condition.code),
        severity: ReferenceView.render(condition.severity),
        body_sites: ReferenceView.render(condition.body_sites),
        stage: ReferenceView.render(condition.stage),
        evidences: ReferenceView.render(condition.evidences),
        asserted_date: DateView.render_date(condition.asserted_date),
        onset_date: DateView.render_datetime(condition.onset_date)
      }
      |> Map.merge(render_source(condition.source))
    end)
  end

  defp render(:observations, observations) do
    Enum.map(observations, fn observation ->
      observation
      |> Map.take(~w(primary_source comment)a)
      |> Map.merge(%{
        id: UUIDView.render(observation._id),
        issued: DateView.render_datetime(observation.issued),
        based_on: ReferenceView.render(observation.based_on),
        method: ReferenceView.render(observation.method),
        categories: ReferenceView.render(observation.categories),
        context: ReferenceView.render(observation.context),
        interpretation: ReferenceView.render(observation.interpretation),
        code: ReferenceView.render(observation.code),
        body_site: ReferenceView.render(observation.body_site),
        reference_ranges: ReferenceView.render(observation.reference_ranges),
        components: ReferenceView.render(observation.components)
      })
      |> Map.merge(ReferenceView.render_effective_at(observation.effective_at))
      |> Map.merge(render_source(observation.source))
      |> Map.merge(ReferenceView.render_value(observation.value))
    end)
  end

  defp render(:risk_assessments, risk_assessments) do
    Enum.map(risk_assessments, fn risk_assessment ->
      risk_assessment
      |> Map.take(~w(mitigation comment)a)
      |> Map.merge(%{
        id: UUIDView.render(risk_assessment.id),
        context: ReferenceView.render(risk_assessment.context),
        code: ReferenceView.render(risk_assessment.code),
        asserted_date: DateView.render_datetime(risk_assessment.asserted_date),
        method: ReferenceView.render(risk_assessment.method),
        performer: render(risk_assessment.performer),
        basis: ReferenceView.render(risk_assessment.basis),
        predictions: ReferenceView.render(risk_assessment.predictions)
      })
      |> Map.merge(ReferenceView.render_reason(risk_assessment.reason))
    end)
  end

  defp render(:devices, devices) do
    Enum.map(devices, fn device ->
      device
      |> Map.take(~w(primary_source lot_number manufacturer model version note)a)
      |> Map.merge(%{
        id: UUIDView.render(device.id),
        context: ReferenceView.render(device.context),
        asserted_date: DateView.render_datetime(device.asserted_date),
        usage_period: ReferenceView.render(device.usage_period),
        type: ReferenceView.render(device.type),
        manufacture_date: DateView.render_datetime(device.manufacture_date),
        expiration_date: DateView.render_datetime(device.expiration_date)
      })
      |> Map.merge(render_source(device.source))
    end)
  end

  defp render(:medication_statements, medication_statements) do
    Enum.map(medication_statements, fn medication_statement ->
      medication_statement
      |> Map.take(~w(effective_period primary_source note dosage)a)
      |> Map.merge(%{
        id: UUIDView.render(medication_statement.id),
        based_on: ReferenceView.render(medication_statement.based_on),
        medication_code: ReferenceView.render(medication_statement.medication_code),
        context: ReferenceView.render(medication_statement.context),
        asserted_date: DateView.render_datetime(medication_statement.asserted_date)
      })
      |> Map.merge(render_source(medication_statement.source))
    end)
  end

  defp render(:diagnostic_reports, diagnostic_reports) do
    Enum.map(diagnostic_reports, fn diagnostic_report ->
      diagnostic_report
      |> Map.take(~w(primary_source conclusion)a)
      |> Map.merge(%{
        id: UUIDView.render(diagnostic_report.id),
        based_on: ReferenceView.render(diagnostic_report.based_on),
        origin_episode: ReferenceView.render(diagnostic_report.origin_episode),
        category: ReferenceView.render(diagnostic_report.category),
        code: ReferenceView.render(diagnostic_report.code),
        encounter: ReferenceView.render(diagnostic_report.encounter),
        issued: DateView.render_datetime(diagnostic_report.issued),
        recorded_by: ReferenceView.render(diagnostic_report.recorded_by),
        results_interpreter: ReferenceView.render(diagnostic_report.results_interpreter),
        managing_organization: ReferenceView.render(diagnostic_report.managing_organization),
        conclusion_code: ReferenceView.render(diagnostic_report.conclusion_code)
      })
      |> Map.merge(ReferenceView.render_effective_at(diagnostic_report.effective))
      |> Map.merge(ReferenceView.render_source(diagnostic_report.source))
    end)
  end

  def render(%Core.Reference{} = reference),
    do: %{identifier: ReferenceView.render(reference.identifier)}

  def render(value), do: value

  def render_source(%Core.Source{type: "performer", value: value}),
    do: %{performer: render(value)}

  def render_source(%Core.Source{type: "asserter", value: value}), do: %{asserter: render(value)}

  def render_source(%Core.Source{type: type, value: value}) do
    %{String.to_atom(type) => ReferenceView.render(value)}
  end
end
