defmodule Core.DiagnosticReports.Source do
  @moduledoc false

  use Ecto.Schema

  alias Core.CodeableConcept
  alias Core.Executor
  alias Core.Validators.DictionaryReference
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one(:report_origin, CodeableConcept)
    embeds_one(:performer, Executor)
  end

  def changeset(%__MODULE__{} = source, params) do
    source
    |> cast(params, [])
    |> cast_embed(:report_origin)
    |> cast_embed(:performer)
  end

  def encounter_package_changeset(%__MODULE__{} = source, params, primary_source, client_id) do
    source
    |> cast(params, [])
    |> cast_embed(:report_origin)
    |> validate_change(:report_origin, &DictionaryReference.validate_change/2)
    |> validate_performer(primary_source, client_id)
  end

  defp validate_performer(changeset, primary_source, client_id) do
    if primary_source do
      cast_embed(changeset, :performer, with: &Executor.reference_changeset(&1, &2, client_id))
    else
      if get_change(changeset, :report_origin) do
        changeset
      else
        cast_embed(changeset, :performer, with: &Executor.text_changeset(&1, &2))
      end
    end
  end
end
