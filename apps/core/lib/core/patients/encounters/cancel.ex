defmodule Core.Patients.Encounters.Cancel do
  @moduledoc false

  alias Core.Conditions
  alias Core.DateView
  alias Core.Encounter
  alias Core.Mongo
  alias Core.Observations
  alias Core.Patients.AllergyIntolerances
  alias Core.Patients.Immunizations
  alias Core.ReferenceView
  alias Core.UUIDView

  require Logger

  @patient_collection Core.Patient.metadata().collection
  @observation_collection Core.Observation.metadata().collection
  @condition_collection Core.Condition.metadata().collection

  @entered_in_error "entered_in_error"

  @entities_meta %{
    "allergy_intolerances" => [status: "verification_status"],
    "immunizations" => [status: "status"],
    "conditions" => [status: "verification_status"],
    "observations" => [status: "status"]
  }

  @doc """
  Performs validation by comparing encounter packages which created retrieved from job signed data and database
  Package entities except `encounter` are MapSet's to ignore position in list
  """
  def validate_cancellation(decoded_content, %Encounter{} = encounter, patient_id_hash) do
    encounter_request_package = create_encounter_package_from_request(decoded_content)

    with {:ok, encounter_package} <- create_encounter_package(encounter, patient_id_hash, decoded_content),
         :ok <- validate_enounter_packages(encounter_package, encounter_request_package),
         :ok <- validate_conditions(decoded_content) do
      :ok
    end
  end

  def proccess_cancellation(patient, user_id, package_data) do
    with {:ok, entities_to_update} <- filter_entities_to_update(package_data),
         :ok <- update_observations_conditions_status(user_id, entities_to_update),
         :ok <- update_patient_entities(patient, user_id, package_data, entities_to_update) do
      :ok
    end
  end

  defp filter_entities_to_update(package_data) do
    @entities_meta
    |> Map.keys()
    |> Enum.map(fn key ->
      [status: status_field] = @entities_meta[key]

      entities_id =
        package_data
        |> Map.get(key, [])
        |> get_in([Access.filter(&(&1[status_field] == @entered_in_error)), "id"])

      {key, entities_id}
    end)
    |> Enum.reject(fn {_key, entities} -> entities == [] end)
    |> Enum.into(%{})
    |> wrap_ok()
  end

  defp update_observations_conditions_status(user_id, entities_data) do
    user_uuid = Mongo.string_to_uuid(user_id)
    now = DateTime.utc_now()

    update_status = fn ids, status_field, collection ->
      uuids = Enum.map(ids, &Mongo.string_to_uuid(&1))

      with {:ok, _} <-
             Mongo.update_many(collection, %{"_id" => %{"$in" => uuids}}, %{
               "$set" => %{
                 status_field => @entered_in_error,
                 "updated_by" => user_uuid,
                 "updated_at" => now
               }
             }) do
        :ok
      else
        err ->
          Logger.error("Fail to update #{collection} #{status_field}: #{inspect(err)}")
          err
      end
    end

    entities_data
    |> Map.take(["observations", "conditions"])
    |> Enum.map(fn
      {"observations", entities_id} ->
        update_status.(entities_id, "status", @observation_collection)

      {"conditions", entities_id} ->
        update_status.(entities_id, "verification_status", @condition_collection)
    end)
    |> Enum.all?(&Kernel.==(&1, :ok))
    |> case do
      true -> :ok
      _ -> {:error, "Fail to update encounter package entities"}
    end
  end

  defp update_patient_entities(patient, user_id, %{"encounter" => encounter}, entities_data) do
    user_uuid = Mongo.string_to_uuid(user_id)
    update_data = %{"updated_by" => user_uuid, "updated_at" => DateTime.utc_now()}

    update_patient_data =
      update_data
      |> update_allergies_immunizations(user_uuid, entities_data)
      |> update_diagnoses(patient, encounter)
      |> update_encounter(user_uuid, encounter)

    with {:ok, _} <- Mongo.update_one(@patient_collection, %{"_id" => patient["_id"]}, %{"$set" => update_patient_data}) do
      :ok
    end
  end

  defp update_allergies_immunizations(update_data, user_uuid, entities_data) do
    entities_data = Map.take(entities_data, ["allergy_intolerances", "immunizations"])

    for {entity_key, entities_ids} <- entities_data, id <- entities_ids do
      status_field = @entities_meta[entity_key][:status]
      add_path = &("#{entity_key}.#{id}." <> &1)

      %{
        add_path.(status_field) => @entered_in_error,
        add_path.("updated_by") => user_uuid,
        add_path.("updated_at") => DateTime.utc_now()
      }
    end
    |> Enum.reduce(update_data, fn change, acc -> Map.merge(acc, change) end)
  end

  defp update_diagnoses(update_data, _patient, %{"status" => @entered_in_error}), do: update_data

  defp update_diagnoses(update_data, patient, encounter) do
    encounter_uuid = Mongo.string_to_uuid(encounter["id"])
    episode_path = ["encounters", encounter["id"], "episode", "identifier", "value"]

    with %BSON.Binary{} = episode_uuid <- get_in(patient, episode_path) do
      episode_id = UUID.binary_to_string!(episode_uuid.binary)
      diagnoses_history = patient["episodes"][episode_id]["diagnoses_history"]

      updated_diagnoses_history =
        Enum.map(diagnoses_history, fn diagnos ->
          if diagnos["evidence"]["identifier"]["value"] == encounter_uuid do
            %{diagnos | "is_active" => false}
          else
            diagnos
          end
        end)

      Map.merge(update_data, %{"episodes.#{episode_id}.diagnoses_history" => updated_diagnoses_history})
    else
      _ -> update_data
    end
  end

  defp update_encounter(update_data, user_uuid, %{"id" => encounter_id} = encounter) do
    add_path = &("encounters.#{encounter_id}." <> &1)

    encounter_update_data = %{
      add_path.("cancellation_reason") => encounter["cancellation_reason"],
      add_path.("explanatory_letter") => encounter["explanatory_letter"],
      add_path.("updated_by") => user_uuid,
      add_path.("updated_at") => DateTime.utc_now()
    }

    encounter_update_data =
      if encounter["status"] == @entered_in_error do
        Map.merge(encounter_update_data, %{add_path.("status") => @entered_in_error})
      else
        encounter_update_data
      end

    Map.merge(update_data, encounter_update_data)
  end

  defp get_entities_to_load(decoded_content) do
    available_entities = Map.keys(@entities_meta)

    decoded_content
    |> Map.delete("encounter")
    |> Map.keys()
    |> Enum.filter(&(&1 in available_entities))
  end

  defp create_encounter_package(%Encounter{id: encounter_uuid} = encounter, patient_id_hash, decoded_content) do
    decoded_content
    |> filter_entities_to_compare()
    |> Enum.reduce(%{}, fn {entity_key, entity_ids}, acc ->
      entity_key_atom = String.to_atom(entity_key)
      entities = get_entities(entity_key, entity_ids, patient_id_hash, encounter_uuid)
      entities = entity_key_atom |> render(entities) |> MapSet.new()

      Map.put(acc, entity_key_atom, entities)
    end)
    |> Map.put(:encounter, render(:encounter, encounter))
    |> wrap_ok()
  end

  defp create_encounter_package_from_request(decoded_content) do
    entities_to_load = get_entities_to_load(decoded_content)

    entity_creators = %{
      "conditions" => &Core.Condition.create/1,
      "allergy_intolerances" => &Core.AllergyIntolerance.create/1,
      "immunizations" => &Core.Immunization.create/1,
      "observations" => &Core.Observation.create/1
    }

    entities_to_load
    |> Enum.reduce(%{}, fn entity_key, acc ->
      entity_key_atom = String.to_atom(entity_key)
      entities = Enum.map(decoded_content[entity_key], &entity_creators[entity_key].(&1))
      entities = entity_key_atom |> render(entities) |> MapSet.new()

      Map.put(acc, entity_key_atom, entities)
    end)
    |> Map.put(
      :encounter,
      render(:encounter, Core.Encounter.create(decoded_content["encounter"]))
    )
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

  defp validate_enounter_packages(package1, package2) do
    if package1 == package2 do
      :ok
    else
      # todo: remove after test
      if Mix.env() == :prod do
        IO.puts("encounter package from db: #{inspect(package1)}")
        IO.puts("encounter package from request: #{inspect(package2)}")
      end

      {:ok, %{"error" => "Submitted signed content does not correspond to previously created content"}, 409}
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

  defp get_entities("allergy_intolerances", ids, patient_id_hash, encounter_uuid) do
    patient_id_hash
    |> AllergyIntolerances.get_by_encounter_id(encounter_uuid)
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

  defp render(:encounter, encounter) do
    %{
      id: UUIDView.render(encounter.id),
      date: DateView.render_date(encounter.date),
      visit: ReferenceView.render(encounter.visit),
      episode: ReferenceView.render(encounter.episode),
      class: ReferenceView.render(encounter.class),
      type: ReferenceView.render(encounter.type),
      incoming_referrals: ReferenceView.render(encounter.incoming_referrals),
      performer: render(encounter.performer),
      reasons: ReferenceView.render(encounter.reasons),
      diagnoses: ReferenceView.render(encounter.diagnoses),
      actions: ReferenceView.render(encounter.actions),
      division: ReferenceView.render(encounter.division)
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
        date: DateView.render_date(immunization.date),
        legal_entity: ReferenceView.render(immunization.legal_entity),
        expiration_date: DateView.render_date(immunization.expiration_date),
        site: ReferenceView.render(immunization.site),
        route: ReferenceView.render(immunization.route),
        dose_quantity: ReferenceView.render(immunization.dose_quantity),
        reactions: ReferenceView.render(immunization.reactions),
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
        onset_date: DateView.render_date(condition.onset_date)
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

  def render(%Core.Reference{} = reference), do: %{identifier: ReferenceView.render(reference.identifier)}
  def render(value), do: value

  def render_source(%Core.Source{type: "performer", value: value}), do: %{performer: render(value)}
  def render_source(%Core.Source{type: "asserter", value: value}), do: %{asserter: render(value)}

  def render_source(%Core.Source{type: type, value: value}) do
    %{String.to_atom(type) => ReferenceView.render(value)}
  end

  defp wrap_ok(value), do: {:ok, value}
end
