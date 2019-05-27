defmodule Core.Validators.MedicationRequestReference do
  @moduledoc false

  alias Core.Encryptor
  import Core.ValidationError

  @worker Application.get_env(:core, :rpc_worker)

  def validate(medication_request_id, options) do
    patient_id =
      options
      |> Keyword.get(:patient_id_hash)
      |> Encryptor.decrypt()

    case @worker.run("ops", OPS.Rpc, :medication_request_by_id, [to_string(medication_request_id)]) do
      %{person_id: ^patient_id} ->
        :ok

      _ ->
        error(options, "Medication request with such ID is not found")
    end
  end
end
