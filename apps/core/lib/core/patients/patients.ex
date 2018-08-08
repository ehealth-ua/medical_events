defmodule Core.Patients do
  @moduledoc false

  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients.Validators
  alias Core.Request
  alias Core.Requests
  alias Core.Requests.VisitCreateRequest
  alias Core.Validators.Error
  alias Core.Validators.JsonSchema
  alias Core.Validators.Signature
  alias EView.Views.ValidationError
  import Core.Condition
  import Core.Encounter
  import Core.Episode
  import Core.Immunization
  import Core.Observation
  import Core.Visit

  @collection Patient.metadata().collection
  @digital_signature Application.get_env(:core, :microservices)[:digital_signature]
  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  @status_active Patient.status(:active)

  def get_by_id(id) do
    Mongo.find_one(@collection, %{"_id" => id})
  end

  def produce_create_visit(%{"id" => id} = params) do
    with %{} = patient <- get_by_id(id),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:visit_create, Map.delete(params, "id")),
         {:ok, request, visit_create_request} <- Requests.create(VisitCreateRequest, params),
         :ok <- @kafka_producer.publish_medical_event(visit_create_request) do
      {:ok, request}
    end
  end

  def consume_create_visit(%VisitCreateRequest{_id: id, episodes: episodes, visits: visits} = request) do
    visits = Enum.into(visits || [], %{}, &{Map.get(&1, "id"), create_visit(&1)})
    episodes = Enum.into(episodes || [], %{}, &{Map.get(&1, "id"), create_episode(&1)})

    case collect_signed_data(request) do
      {:error, error} ->
        Requests.update(id, Request.status(:processed), error)
        :ok

      %{
        "encounters" => encounters,
        "conditions" => conditions,
        "observations" => observations,
        # "allergy_intolerances" => allergy_intolerances,
        "immunizations" => immunizations
      } ->
        set =
          %{}
          |> add_to_set(visits, "visits")
          |> add_to_set(episodes, "episodes")
          # |> add_to_set(allergy_intolerances, "allergy_intolerances")
          |> add_to_set(immunizations, "immunizations")

        Mongo.update_one(@collection, %{"id" => id}, %{"$set" => set})
    end
  end

  defp add_to_set(set, values, path) do
    Enum.reduce(values, set, fn value, acc ->
      value_updates =
        Enum.reduce(value, %{}, fn {k, v}, value_acc ->
          Map.put(value_acc, "#{path}.#{value["id"]}.#{k}", v)
        end)

      Map.merge(acc, value_updates)
    end)
  end

  defp collect_signed_data(%VisitCreateRequest{id: id, signed_data: signed_data}) do
    initial_data = %{
      "encounters" => %{},
      "conditions" => %{},
      "observations" => %{},
      # "allergy_intolerances" => %{},
      "immunizations" => %{}
    }

    signed_data
    |> Enum.with_index()
    |> Enum.reduce_while(initial_data, fn {signed_content, index}, acc ->
      with {:ok, %{"data" => data}} <- @digital_signature.decode(signed_content, []),
           {:ok, %{"content" => content, "signer" => signer}} <- Signature.validate(data),
           :ok <- JsonSchema.validate(:visit_create_signed_content, content) do
        encounters = Enum.into(Map.get(content, "encounters", []), %{}, &{Map.get(&1, "id"), create_encounter(&1)})
        conditions = Enum.into(Map.get(content, "conditions", []), %{}, &{Map.get(&1, "id"), create_condition(&1)})

        observations =
          Enum.into(Map.get(content, "observations", []), %{}, &{Map.get(&1, "id"), create_observation(&1)})

        # allergy_intolerances =
        #   Enum.into(
        #     Map.get(content, "allergy_intolerances"),
        #     %{},
        #     &{Map.get(&1, "id"), create_allergy_intolerance(&1)}
        #   )

        immunizations =
          Enum.into(Map.get(content, "immunizations", []), %{}, &{Map.get(&1, "id"), create_immunization(&1)})

        {:cont,
         %{
           acc
           | "encounters" => Map.merge(acc["encounters"], encounters),
             "conditions" => Map.merge(acc["conditions"], conditions),
             "observations" => Map.merge(acc["observations"], observations),
             # "allergy_intolerances" => Map.merge(acc["allergy_intolerances"], allergy_intolerances),
             "immunizations" => Map.merge(acc["immunizations"], immunizations)
         }}
      else
        {:error, error} ->
          {:halt, {:error, Jason.encode!(ValidationError.render("422.json", %{schema: error}))}}
      end
    end)
  end
end
