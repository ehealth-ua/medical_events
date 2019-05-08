defmodule Core.Encounter do
  @moduledoc false

  use Core.Schema

  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.Diagnosis
  alias Core.Reference

  @status_finished "finished"
  @status_entered_in_error "entered_in_error"

  def status(:finished), do: @status_finished
  def status(:entered_in_error), do: @status_entered_in_error

  embedded_schema do
    field(:id, presence: true, mongo_uuid: true)
    field(:status, presence: true)
    field(:status_history)

    field(:class,
      presence: true,
      reference: [path: "class"],
      dictionary_reference: [referenced_field: "system", field: "code"]
    )

    field(:type,
      presence: true,
      dictionary_reference: [path: "type", referenced_field: "system", field: "code"]
    )

    field(:incoming_referral, reference: [path: "incoming_referral"])
    field(:duration)

    field(:reasons,
      presence: true,
      dictionary_reference: [path: "reasons", referenced_field: "system", field: "code"]
    )

    field(:diagnoses, presence: true, reference: [path: "diagnoses"])
    field(:service_provider)
    field(:division, reference: [path: "division"])
    field(:actions, presence: true, dictionary_reference: [path: "actions", referenced_field: "system", field: "code"])
    field(:signed_content_links)
    field(:performer, presence: true, reference: [path: "performer"])
    field(:episode, presence: true, reference: [path: "episode"])
    field(:visit, presence: true, reference: [path: "visit"])
    field(:date, presence: true)
    field(:explanatory_letter)

    field(:cancellation_reason,
      dictionary_reference: [path: "cancellation_reason", referenced_field: "system", field: "code"]
    )

    field(:prescriptions)
    field(:supporting_info, reference: [path: "supporting_info"])

    timestamps()
    changed_by()
  end

  def create(data) do
    struct(
      __MODULE__,
      Enum.map(data, fn
        {"episode", v} ->
          {:episode, Reference.create(v)}

        {"visit", v} ->
          {:visit, Reference.create(v)}

        {"division", nil} ->
          {:division, nil}

        {"division", v} ->
          {:division, Reference.create(v)}

        {"diagnoses", v} ->
          {:diagnoses, Enum.map(v, &Diagnosis.create/1)}

        {"actions", v} ->
          {:actions, Enum.map(v, &CodeableConcept.create/1)}

        {"reasons", v} ->
          {:reasons, Enum.map(v, &CodeableConcept.create/1)}

        {"class", v} ->
          {:class, Coding.create(v)}

        {"type", v} ->
          {:type, CodeableConcept.create(v)}

        {"performer", v} ->
          {:performer, Reference.create(v)}

        {"incoming_referral", nil} ->
          {:incoming_referral, nil}

        {"incoming_referral", v} ->
          {:incoming_referral, Reference.create(v)}

        {"service_provider", v} ->
          {:service_provider, Reference.create(v)}

        {"date", v} ->
          {:date, create_datetime(v)}

        {"cancellation_reason", v} ->
          {:cancellation_reason, CodeableConcept.create(v)}

        {"supporting_info", nil} ->
          {:supporting_info, nil}

        {"supporting_info", v} ->
          {:supporting_info, Enum.map(v, &Reference.create/1)}

        {k, v} ->
          {String.to_atom(k), v}
      end)
    )
  end
end
