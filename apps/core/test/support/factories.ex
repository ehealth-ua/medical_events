defmodule Core.Factories do
  @moduledoc false

  use ExMachina

  alias Core.AllergyIntolerance
  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.Condition
  alias Core.DiagnosesHistory
  alias Core.Diagnosis
  alias Core.Encounter
  alias Core.Episode
  alias Core.Evidence
  alias Core.Identifier
  alias Core.Immunization
  alias Core.Job
  alias Core.Mongo
  alias Core.Observation
  alias Core.Observations.Component
  alias Core.Observations.EffectiveAt
  alias Core.Observations.ReferenceRange
  alias Core.Observations.Value
  alias Core.Observations.Values.Quantity
  alias Core.Patient
  alias Core.Patients
  alias Core.Patients.Immunizations.Explanation
  alias Core.Patients.Immunizations.Reaction
  alias Core.Patients.Immunizations.VaccinationProtocol
  alias Core.Period
  alias Core.Reference
  alias Core.ServiceRequest
  alias Core.ServiceRequests.Occurence
  alias Core.Source
  alias Core.Stage
  alias Core.StatusHistory
  alias Core.Visit

  def patient_factory do
    visits = build_list(2, :visit)

    visits =
      Enum.into(visits, %{}, fn %{id: %BSON.Binary{binary: id}} = visit ->
        {UUID.binary_to_string!(id), visit}
      end)

    episodes = build_list(2, :episode)

    episodes =
      Enum.into(episodes, %{}, fn %{id: %BSON.Binary{binary: id}} = episode ->
        {UUID.binary_to_string!(id), episode}
      end)

    encounters = build_list(2, :encounter)

    encounters =
      Enum.into(encounters, %{}, fn %{id: %BSON.Binary{binary: id}} = encounter ->
        {UUID.binary_to_string!(id), encounter}
      end)

    immunizations = build_list(2, :immunization)

    immunizations =
      Enum.into(immunizations, %{}, fn %{id: %BSON.Binary{binary: id}} = immunization ->
        {UUID.binary_to_string!(id), immunization}
      end)

    allergy_intolerances = build_list(2, :allergy_intolerance)

    allergy_intolerances =
      Enum.into(allergy_intolerances, %{}, fn %{id: %BSON.Binary{binary: id}} = allergy_intolerance ->
        {UUID.binary_to_string!(id), allergy_intolerance}
      end)

    id = Patients.get_pk_hash(UUID.uuid4())
    user_id = UUID.uuid4()

    %Patient{
      _id: id,
      status: Patient.status(:active),
      visits: visits,
      episodes: episodes,
      encounters: encounters,
      immunizations: immunizations,
      allergy_intolerances: allergy_intolerances,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      inserted_by: user_id,
      updated_by: user_id
    }
  end

  def visit_factory do
    id = UUID.uuid4()

    %Visit{
      id: Mongo.string_to_uuid(id),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      inserted_by: Mongo.string_to_uuid(id),
      updated_by: Mongo.string_to_uuid(id),
      period: build(:period)
    }
  end

  def period_factory do
    %Period{
      start: DateTime.utc_now(),
      end: DateTime.utc_now()
    }
  end

  def allergy_intolerance_factory do
    id = Mongo.string_to_uuid(UUID.uuid4())
    now = DateTime.utc_now()

    %AllergyIntolerance{
      id: id,
      clinical_status: AllergyIntolerance.clinical_status(:active),
      verification_status: AllergyIntolerance.verification_status(:confirmed),
      type: "allergy",
      category: "food",
      criticality: "low",
      code: codeable_concept_coding(system: "eHealth/allergy_intolerance_codes", code: "227493005"),
      context: reference_coding(system: "eHealth/resources", code: "encounter"),
      onset_date_time: now,
      asserted_date: now,
      last_occurrence: now,
      primary_source: true,
      source:
        build(
          :source,
          type: "asserter",
          value: reference_coding(system: "eHealth/resources", code: "employee")
        ),
      inserted_at: now,
      updated_at: now,
      inserted_by: id,
      updated_by: id
    }
  end

  def immunization_factory do
    id = Mongo.string_to_uuid(UUID.uuid4())
    now = DateTime.utc_now()

    %Immunization{
      id: id,
      inserted_at: now,
      updated_at: now,
      inserted_by: id,
      updated_by: id,
      status: Immunization.status(:completed),
      not_given: false,
      vaccine_code: codeable_concept_coding(system: "eHealth/vaccine_codes", code: "FLUVAX"),
      context: reference_coding(system: "eHealth/resources", code: "encounter"),
      date: now,
      primary_source: true,
      source:
        build(
          :source,
          type: "performer",
          value: reference_coding(system: "eHealth/resources", code: "employee")
        ),
      manufacturer: "VacinePro Manufacturer",
      lot_number: "AAJN11K",
      expiration_date: now,
      legal_entity: reference_coding(system: "eHealth/resources", code: "legal_entity"),
      site: codeable_concept_coding(system: "eHealth/body_sites", code: "1"),
      route: codeable_concept_coding(system: "eHealth/vaccination_routes", code: "IM"),
      dose_quantity: build(:quantity, system: "eHealth/ucum/units"),
      explanation: build(:explanation),
      reactions: [build(:reaction)],
      vaccination_protocols: [build(:vaccination_protocol)]
    }
  end

  def explanation_factory do
    %Explanation{
      type: "reasons",
      value: [build(:codeable_concept)]
    }
  end

  def reaction_factory do
    %Reaction{
      detail: reference_coding(system: "eHealth/resources", code: "observation")
    }
  end

  def vaccination_protocol_factory do
    %VaccinationProtocol{
      dose_sequence: 1,
      description: "Vaccination Protocol Sequence 1",
      authority: codeable_concept_coding(system: "eHealth/vaccination_authorities", code: "WVO"),
      series: "Vaccination Series 1",
      series_doses: 2,
      target_diseases: [
        codeable_concept_coding(system: "eHealth/vaccination_target_diseases", code: "1857005")
      ],
      dose_status: codeable_concept_coding(system: "eHealth/vaccination_dose_statuses", code: "1"),
      dose_status_reason:
        codeable_concept_coding(
          system: "eHealth/vaccination_dose_statuse_reasons",
          code: "coldchbrk"
        )
    }
  end

  def job_factory do
    %Job{
      _id: Mongo.generate_id(),
      hash: :crypto.hash(:md5, to_string(DateTime.to_unix(DateTime.utc_now()))),
      eta: NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601(),
      status_code: 200,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      status: Job.status(:pending),
      response: ""
    }
  end

  def observation_factory do
    user_id = UUID.uuid4()
    now = DateTime.utc_now()

    %Observation{
      _id: Mongo.string_to_uuid(UUID.uuid4()),
      status: Observation.status(:valid),
      categories: [codeable_concept_coding(system: "eHealth/observation_categories", code: "1")],
      code: codeable_concept_coding(system: "eHealth/LOINC/observation_codes", code: "8310-5"),
      comment: "some comment",
      patient_id: Patients.get_pk_hash(UUID.uuid4()),
      based_on: [reference_coding(system: "eHealth/resources", code: "service_request")],
      context: reference_coding(system: "eHealth/resources", code: "encounter"),
      effective_at: %EffectiveAt{type: "effective_date_time", value: now},
      issued: now,
      primary_source: true,
      source:
        build(
          :source,
          type: "performer",
          value: reference_coding(system: "eHealth/resources", code: "employee")
        ),
      interpretation: codeable_concept_coding(system: "eHealth/observation_interpretations"),
      method: codeable_concept_coding(system: "eHealth/observation_methods"),
      value: build(:value),
      body_site: codeable_concept_coding(system: "eHealth/body_sites"),
      reference_ranges: [
        build(
          :reference_range,
          type: codeable_concept_coding(system: "eHealth/reference_range_types"),
          applies_to: [codeable_concept_coding(system: "eHealth/reference_range_applications")]
        )
      ],
      components:
        build_list(
          2,
          :component,
          code: codeable_concept_coding(system: "eHealth/LOINC/observation_codes"),
          interpretation: codeable_concept_coding(system: "eHealth/observation_interpretations"),
          reference_ranges: [
            build(
              :reference_range,
              type: codeable_concept_coding(system: "eHealth/reference_range_types"),
              applies_to: [
                codeable_concept_coding(system: "eHealth/reference_range_applications")
              ]
            )
          ]
        ),
      inserted_at: now,
      updated_at: now,
      inserted_by: Mongo.string_to_uuid(user_id),
      updated_by: Mongo.string_to_uuid(user_id)
    }
  end

  def source_factory do
    %Source{type: "performer", value: build(:reference)}
  end

  def reference_range_factory do
    %ReferenceRange{
      low: build(:quantity),
      high: build(:quantity),
      type: build(:codeable_concept),
      applies_to: build_list(2, :codeable_concept),
      age: %{
        low: build(:quantity, comparator: ">", unit: "years"),
        high: build(:quantity, comparator: "<", unit: "years")
      },
      text: "some text"
    }
  end

  def component_factory do
    %Component{
      code: build(:codeable_concept),
      value: build(:value),
      interpretation: build(:codeable_concept),
      reference_ranges: build_list(2, :reference_range)
    }
  end

  def quantity_factory do
    %Quantity{
      value: :rand.uniform(100),
      comparator: "<",
      unit: "mg",
      system: "eHealth/ucum/units",
      code: "mg"
    }
  end

  def encounter_factory do
    id = UUID.uuid4()
    now = DateTime.utc_now()

    %Encounter{
      id: Mongo.string_to_uuid(UUID.uuid4()),
      status: Encounter.status(:finished),
      date: now,
      episode: reference_coding(system: "eHealth/resources", code: "episode"),
      performer: reference_coding(system: "eHealth/resources", code: "employee"),
      visit: reference_coding(system: "eHealth/resources", code: "visit"),
      class: build(:coding, system: "eHealth/encounter_classes", code: "PHC"),
      type: codeable_concept_coding(system: "eHealth/encounter_types", code: "AMB"),
      reasons: [codeable_concept_coding(system: "eHealth/ICPC2/reasons", code: "reason")],
      diagnoses: [build(:diagnosis)],
      cancellation_reason: codeable_concept_coding(system: "eHealth/cancellation_reasons", code: "misspelling"),
      incoming_referrals: [reference_coding(system: "eHealth/resources", code: "service_request")],
      actions: [codeable_concept_coding(system: "eHealth/ICPC2/actions", code: "action")],
      division: reference_coding(system: "eHealth/resources", code: "division"),
      service_provider: build(:reference),
      explanatory_letter: "some explanations",
      prescriptions: "Дієта №1",
      inserted_at: now,
      updated_at: now,
      inserted_by: Mongo.string_to_uuid(id),
      updated_by: Mongo.string_to_uuid(id)
    }
  end

  def episode_factory do
    id = UUID.uuid4()
    date = to_string(Date.utc_today())
    diagnoses_history = build_list(1, :diagnoses_history)

    %Episode{
      id: Mongo.string_to_uuid(UUID.uuid4()),
      status: Episode.status(:active),
      current_diagnoses: Map.get(hd(diagnoses_history), :diagnoses),
      closing_summary: "closing summary",
      status_reason: build(:codeable_concept),
      explanatory_letter: "explanatory letter",
      status_history: build_list(1, :status_history),
      diagnoses_history: diagnoses_history,
      type: build(:coding, code: "primary_care", system: "eHealth/episode_types"),
      name: "ОРВИ 2018",
      managing_organization: reference_coding(code: "legal_entity"),
      period: build(:period, start: date, end: date),
      care_manager: reference_coding(code: "employee"),
      referral_requests: [reference_coding(system: "eHealth/resources", code: "service_request")],
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      inserted_by: Mongo.string_to_uuid(id),
      updated_by: Mongo.string_to_uuid(id)
    }
  end

  def diagnoses_history_factory do
    %DiagnosesHistory{
      date: DateTime.utc_now(),
      evidence: build(:reference),
      diagnoses: build_list(2, :diagnosis),
      is_active: true
    }
  end

  def diagnosis_factory do
    %Diagnosis{
      condition: reference_coding(system: "eHealth/resources", code: "condition"),
      role: codeable_concept_coding(system: "eHealth/diagnosis_roles", code: "primary"),
      code: codeable_concept_coding(system: "eHealth/ICPC2/condition_codes", code: "R80"),
      rank: Enum.random(1..1000)
    }
  end

  def value_factory do
    %Value{type: "string", value: "some value"}
  end

  def codeable_concept_factory do
    %CodeableConcept{
      coding: [build(:coding)],
      text: "code text"
    }
  end

  def coding_factory do
    %Coding{
      system: "eHealth/resources",
      code: "1"
    }
  end

  def reference_factory do
    %Reference{
      identifier: build(:identifier)
    }
  end

  def identifier_factory do
    %Identifier{
      type: build(:codeable_concept),
      value: Mongo.string_to_uuid(UUID.uuid4())
    }
  end

  def stage_factory do
    %Stage{
      summary: build(:codeable_concept)
    }
  end

  def evidence_factory do
    %Evidence{
      codes: [build(:codeable_concept)],
      details: [build(:reference)]
    }
  end

  def condition_factory do
    patient_id = Patients.get_pk_hash(UUID.uuid4())
    user_id = UUID.uuid4()

    %Condition{
      _id: Mongo.string_to_uuid(UUID.uuid4()),
      context: reference_coding(code: "encounter"),
      code: codeable_concept_coding(system: "eHealth/ICD10/condition_codes", code: "R80"),
      clinical_status: "active",
      verification_status: "provisional",
      severity: codeable_concept_coding(system: "eHealth/condition_severities"),
      body_sites: [codeable_concept_coding(system: "eHealth/body_sites")],
      onset_date: DateTime.utc_now(),
      asserted_date: DateTime.utc_now(),
      stage: build(:stage, summary: codeable_concept_coding(system: "eHealth/condition_stages")),
      evidences: [
        build(
          :evidence,
          codes: [codeable_concept_coding(system: "eHealth/ICPC2/reasons", code: "A02")],
          details: [reference_coding(code: "observation")]
        )
      ],
      patient_id: patient_id,
      inserted_by: Mongo.string_to_uuid(user_id),
      updated_by: Mongo.string_to_uuid(user_id),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      source:
        build(
          :source,
          type: "asserter",
          value: reference_coding(system: "eHealth/resources", code: "employee")
        ),
      primary_source: true
    }
  end

  def status_history_factory do
    %StatusHistory{
      status: Episode.status(:active),
      status_reason: codeable_concept_coding(system: "eHealth/episode_closing_reasons"),
      inserted_at: DateTime.utc_now(),
      inserted_by: Mongo.string_to_uuid(UUID.uuid4())
    }
  end

  def service_request_factory do
    patient_id = Patients.get_pk_hash(UUID.uuid4())
    user_id = UUID.uuid4()

    %ServiceRequest{
      _id: Mongo.string_to_uuid(UUID.uuid4()),
      requisition: UUID.uuid4(),
      status: ServiceRequest.status(:active),
      intent: "plan",
      code: codeable_concept_coding(system: "eHealth/SNOMED/procedure_codes", code: "128004"),
      category: codeable_concept_coding(system: "eHealth/SNOMED/service_request_categories", code: "409063005"),
      context: reference_coding(system: "eHealth/resources", code: "encounter"),
      occurence: %Occurence{type: "date_time", value: DateTime.to_iso8601(DateTime.utc_now())},
      performer_type:
        codeable_concept_coding(system: "eHealth/SNOMED/service_request_performer_roles", code: "psychiatrist"),
      requester: reference_coding(system: "eHealth/resources", code: "employee"),
      authored_on: DateTime.to_iso8601(DateTime.utc_now()),
      subject: patient_id,
      inserted_by: Mongo.string_to_uuid(user_id),
      updated_by: Mongo.string_to_uuid(user_id),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  def reference_coding(value \\ nil, attrs) do
    value = value || Mongo.string_to_uuid(UUID.uuid4())

    build(:reference, identifier: build(:identifier, type: codeable_concept_coding(attrs), value: value))
  end

  def codeable_concept_coding(attrs) do
    build(:codeable_concept, coding: [build(:coding, attrs)])
  end

  def insert(factory, args \\ [])

  def insert(:job, args) do
    :job
    |> build(args)
    |> Job.encode_response()
    |> insert_entity()
  end

  def insert(factory, args) do
    factory
    |> build(args)
    |> insert_entity()
  end

  def insert_list(count, factory, args \\ []) do
    for _ <- 1..count, do: insert(factory, args)
  end

  defp insert_entity(entity) do
    {:ok, _} = Mongo.insert_one(entity)
    entity
  end
end
