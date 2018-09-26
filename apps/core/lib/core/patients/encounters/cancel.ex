defmodule Core.Patients.Encounters.Cancel do
  @moduledoc false

  alias Core.Conditions
  alias Core.Encounter
  alias Core.Observations
  alias Core.Patients.AllergyIntolerances
  alias Core.Patients.Encounters
  alias Core.Patients.Immunizations

  @encounter_entered_in_error Encounter.status(:entered_in_error)

  def validate_cancellation(decoded_content, encounter_id, patient_id) do
    entities_to_load = get_entities_to_load(decoded_content)

    {entities, encounter_package} = create_encounter_package(encounter_id, patient_id, entities_to_load)

    encounter_request_package = create_encounter_package_from_request(decoded_content, entities_to_load)

    with :ok <- validate_enounter_packages(encounter_package, encounter_request_package),
         :ok <- validate_conditions(decoded_content),
         :ok <- validate_cancelation_reason(decoded_content) do
      {:ok, entities}
    end
  end

  defp get_entities_to_load(decoded_content) do
    available_entities = ["conditions", "allergy_intolerances", "immunizations", "observations"]

    decoded_content
    |> Map.delete("encounter")
    |> Map.keys()
    |> Enum.filter(&(&1 in available_entities))
  end

  defp create_encounter_package(encounter_id, patient_id, entities_to_load) do
    encounter_uuid = Core.Mongo.string_to_uuid(encounter_id)

    entities_resolvers = %{
      "conditions" => fn -> Conditions.get_by_encounter_id(patient_id, encounter_uuid) end,
      "allergy_intolerances" => fn ->
        AllergyIntolerances.get_by_encounter_id(patient_id, encounter_uuid)
      end,
      "immunizations" => fn -> Immunizations.get_by_encounter_id(patient_id, encounter_uuid) end,
      "observations" => fn -> Observations.get_by_encounter_id(patient_id, encounter_uuid) end
    }

    with {:ok, encounter} <- Encounters.get_by_id(patient_id, encounter_id) do
      entities =
        entities_to_load
        |> Enum.map(fn entity_key ->
          {String.to_atom(entity_key), entities_resolvers[entity_key].()}
        end)
        |> Enum.into(%{})
        |> Map.put(:encounter, encounter)

      encounter_package =
        entities
        |> Enum.map(fn {entity_key, entities} -> {entity_key, filter(entity_key, entities)} end)
        |> Enum.into(%{})

      {entities, encounter_package}
    end
  end

  defp create_encounter_package_from_request(decoded_content, entities_to_load) do
    entity_creators = %{
      "conditions" => &Core.Condition.create/1,
      "allergy_intolerances" => &Core.AllergyIntolerance.create/1,
      "immunizations" => &Core.Immunization.create/1,
      "observations" => &Core.Observation.create/1
    }

    entities_to_load
    |> Enum.map(fn entity_key ->
      entities = Enum.map(decoded_content[entity_key], &entity_creators[entity_key].(&1))

      {:"#{entity_key}", filter(:"#{entity_key}", entities)}
    end)
    |> Enum.into(%{})
    |> Map.put(
      :encounter,
      filter(:encounter, Core.Encounter.create(decoded_content["encounter"]))
    )
  end

  defp validate_enounter_packages(package1, package2) do
    if package1 == package2 do
      :ok
    else
      {:error, {:conflict, "Submitted signed content does not correspond to previously created content"}}
    end
  end

  defp validate_conditions(%{"encounter" => %{"status" => @encounter_entered_in_error}}), do: :ok

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
        {:error, {:conflict, "The condition can not be canceled while encounter is not canceled"}}

      _ ->
        :ok
    end
  end

  defp validate_conditions(_), do: :ok

  defp validate_cancelation_reason(decoded_content) do
    check_system_field = &(&1["system"] == "eHealth/cancellation_reasons")

    decoded_content
    |> get_in(["encounter", "cancellation_reason", "coding", Access.filter(check_system_field)])
    |> length()
    |> case do
      0 -> {:error, {:"422", "Invalid cancellation_reason coding"}}
      _ -> :ok
    end
  end

  defp filter(:encounter, encounter) do
    # status
    %{
      id: Core.UUIDView.render(encounter.id),
      date: Core.ReferenceView.render_date(encounter.date),
      visit: Core.ReferenceView.render(encounter.visit),
      episode: Core.ReferenceView.render(encounter.episode),
      class: Core.ReferenceView.render(encounter.class),
      type: Core.ReferenceView.render(encounter.type),
      incoming_referrals: Core.ReferenceView.render(encounter.incoming_referrals),
      performer: Core.ReferenceView.render(encounter.performer),
      reasons: Core.ReferenceView.render(encounter.reasons),
      diagnoses: Core.ReferenceView.render(encounter.diagnoses),
      actions: Core.ReferenceView.render(encounter.actions),
      division: Core.ReferenceView.render(encounter.division)
    }
  end

  defp filter(:conditions, conditions) do
    # verification_status
    Enum.map(conditions, fn condition ->
      %{
        id: Core.UUIDView.render(condition._id),
        primary_source: condition.primary_source,
        context: Core.ReferenceView.render(condition.context),
        code: Core.ReferenceView.render(condition.code),
        severity: Core.ReferenceView.render(condition.severity),
        body_sites: Core.ReferenceView.render(condition.body_sites),
        stage: Core.ReferenceView.render(condition.stage),
        evidences: Core.ReferenceView.render(condition.evidences),
        asserted_date: Core.ReferenceView.render_date(condition.asserted_date),
        onset_date: Core.ReferenceView.render_date(condition.onset_date)
      }
      |> Map.merge(Core.ReferenceView.render_source(condition.source))
    end)
  end

  defp filter(:allergy_intolerances, allergy_intolerances) do
    Enum.map(allergy_intolerances, fn allergy_intolerance ->
      allergy_intolerance
      |> Map.take(~w(type category criticality primary_source)a)
      |> Map.merge(%{
        id: Core.UUIDView.render(allergy_intolerance.id),
        context: Core.ReferenceView.render(allergy_intolerance.context),
        code: Core.ReferenceView.render(allergy_intolerance.code),
        onset_date_time: Core.ReferenceView.render_date(allergy_intolerance.onset_date_time),
        asserted_date: Core.ReferenceView.render_date(allergy_intolerance.asserted_date),
        last_occurrence: Core.ReferenceView.render_date(allergy_intolerance.last_occurrence)
      })
      |> Map.merge(Core.ReferenceView.render_source(allergy_intolerance.source))
    end)
  end

  defp filter(:immunizations, immunizations) do
    # status
    Enum.map(immunizations, fn immunization ->
      immunization
      |> Map.take(~w(
        not_given
        primary_source
        manufacturer
        lot_number
      )a)
      |> Map.merge(%{
        id: Core.UUIDView.render(immunization.id),
        vaccine_code: Core.ReferenceView.render(immunization.vaccine_code),
        context: Core.ReferenceView.render(immunization.context),
        date: Core.ReferenceView.render_date(immunization.date),
        legal_entity: Core.ReferenceView.render(immunization.legal_entity),
        expiration_date: Core.ReferenceView.render_date(immunization.expiration_date),
        site: Core.ReferenceView.render(immunization.site),
        route: Core.ReferenceView.render(immunization.route),
        dose_quantity: Core.ReferenceView.render(immunization.dose_quantity),
        reactions: Core.ReferenceView.render(immunization.reactions),
        vaccination_protocols: Core.ReferenceView.render(immunization.vaccination_protocols),
        explanation: Core.ReferenceView.render(immunization.explanation)
      })
      |> Map.merge(Core.ReferenceView.render_source(immunization.source))
    end)
  end

  defp filter(:observations, observations) do
    # status
    Enum.map(observations, fn observation ->
      observation
      |> Map.take(~w(primary_source comment)a)
      |> Map.merge(%{
        id: Core.UUIDView.render(observation._id),
        issued: Core.ReferenceView.render_datetime(observation.issued),
        based_on: Core.ReferenceView.render(observation.based_on),
        method: Core.ReferenceView.render(observation.method),
        categories: Core.ReferenceView.render(observation.categories),
        context: Core.ReferenceView.render(observation.context),
        interpretation: Core.ReferenceView.render(observation.interpretation),
        code: Core.ReferenceView.render(observation.code),
        body_site: Core.ReferenceView.render(observation.body_site),
        reference_ranges: Core.ReferenceView.render(observation.reference_ranges),
        components: Core.ReferenceView.render(observation.components)
      })
      |> Map.merge(Core.ReferenceView.render_effective_at(observation.effective_at))
      |> Map.merge(Core.ReferenceView.render_source(observation.source))
      |> Map.merge(Core.ReferenceView.render_value(observation.value))
    end)
  end
end
