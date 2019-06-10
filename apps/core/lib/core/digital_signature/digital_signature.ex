defmodule Core.DigitalSignature do
  @moduledoc false

  use Confex, otp_app: :core
  alias Core.ValidationError
  alias Core.Validators.Error
  alias Core.Validators.Signature
  require Logger

  @rpc_worker Application.get_env(:core, :rpc_worker)

  def decode_and_validate(signed_content) do
    with {:ok, response} <- decode(signed_content) do
      Signature.validate(response)
    else
      {:error, :badrpc} ->
        {:ok, "Failed to decode signed content", 500}

      {:error, error} ->
        {:error, error, 422}
    end
  end

  def decode(signed_content) do
    if config()[:enabled] do
      with {:ok, response} <- @rpc_worker.run("ds_api", API.Rpc, :decode_signed_content, [signed_content]) do
        {:ok, response}
      else
        {:error, :badrpc} ->
          {:error, :badrpc}

        {:error, reason} ->
          Logger.info(inspect(reason))

          Error.dump(%ValidationError{
            description: "Invalid signed content",
            path: "$.signed_data"
          })
      end
    else
      with {:base64, {:ok, binary}} <- {:base64, Base.decode64(signed_content)},
           {:json, {:ok, data}} <- {:json, Jason.decode(binary)} do
        data_is_valid_resp(data)
      else
        {:base64, _} -> base64_error()
        {:json, _} -> invalid_json_error("Malformed encoded content. Probably, you have encoded corrupted JSON.")
      end
    end
  end

  defp data_is_valid_resp(data) do
    signatures = [
      %{
        is_valid: true,
        signer: %{},
        validation_error_message: ""
      }
    ]

    {:ok, %{content: data, signatures: signatures}}
  end

  defp invalid_json_error(error_description) do
    Error.dump(%ValidationError{description: error_description, rule: "invalid", path: "$.signed_content"})
  end

  defp base64_error do
    Error.dump(%ValidationError{description: "Not a base64 string", rule: "invalid", path: "$.signed_content"})
  end
end
