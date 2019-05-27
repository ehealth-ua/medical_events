defmodule Core.Executor do
  @moduledoc false

  use Ecto.Schema
  alias Core.Reference
  import Ecto.Changeset

  @fields_required ~w()a
  @fields_optional ~w(text)a

  @primary_key false
  embedded_schema do
    field(:text, :string)
    embeds_one(:reference, Reference)
  end

  def changeset(%__MODULE__{} = executor, params) do
    executor
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:reference)
  end

  def reference_changeset(
        %__MODULE__{} = executor,
        params,
        client_id,
        required_message \\ "can't be blank"
      ) do
    executor
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> cast_embed(:reference,
      required: true,
      required_message: required_message,
      with:
        &Reference.employee_changeset(&1, &2,
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not an active doctor",
            legal_entity_id: "Employee #{get_in(&2, ~w(identifier value))} doesn't belong to your legal entity"
          ]
        )
    )
  end

  def text_changeset(%__MODULE__{} = executor, params) do
    changeset =
      executor
      |> cast(params, ~w(text)a)
      |> cast_embed(:reference)

    if get_change(changeset, :reference) do
      add_error(changeset, :reference, "performer with type reference must not be filled")
    else
      changeset
    end
  end

  def results_interpreter_text_changeset(%__MODULE__{} = executor, params) do
    changeset =
      executor
      |> cast(params, ~w(text)a)
      |> cast_embed(:reference)

    case get_change(changeset, :reference) do
      nil ->
        changeset

      _ ->
        add_error(
          changeset,
          :reference,
          "results_interpreter with type reference must not be filled"
        )
    end
  end
end
