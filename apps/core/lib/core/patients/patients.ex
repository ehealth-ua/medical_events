defmodule Core.Patients do
  @moduledoc false

  use Confex, otp_app: :core

  alias Core.AllergyIntolerance
  alias Core.Condition
  alias Core.Conditions
  alias Core.DatePeriod
  alias Core.DiagnosesHistory
  alias Core.Encounter
  alias Core.Episode
  alias Core.Immunization
  alias Core.Jobs
  alias Core.Jobs.EpisodeCancelJob
  alias Core.Jobs.EpisodeCloseJob
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.EpisodeUpdateJob
  alias Core.Jobs.PackageCancelJob
  alias Core.Jobs.PackageCreateJob
  alias Core.Mongo
  alias Core.Observation
  alias Core.Patient
  alias Core.Patients.AllergyIntolerances
  alias Core.Patients.Encounters
  alias Core.Patients.Episodes
  alias Core.Patients.Immunizations
  alias Core.Patients.Validators
  alias Core.StatusHistory
  alias Core.Validators.JsonSchema
  alias Core.Validators.Signature
  alias Core.Validators.Vex
  alias Core.Visit
  alias Core.Conditions.Validations, as: ConditionValidations
  alias Core.Observations
  alias Core.Observations.Validations, as: ObservationValidations
  alias Core.Patients.AllergyIntolerances.Validations, as: AllergyIntoleranceValidations
  alias Core.Patients.Episodes.Validations, as: EpisodeValidations
  alias Core.Patients.Encounters.Cancel, as: CancelEncounter
  alias Core.Patients.Encounters.Validations, as: EncounterValidations
  alias Core.Patients.Immunizations.Validations, as: ImmunizationValidations
  alias Core.Patients.Visits.Validations, as: VisitValidations
  alias EView.Views.ValidationError

  require Logger

  @collection Patient.metadata().collection
  @digital_signature Application.get_env(:core, :microservices)[:digital_signature]
  @media_storage Application.get_env(:core, :microservices)[:media_storage]
  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def get_pk_hash(nil), do: nil

  def get_pk_hash(value) do
    :sha256
    |> :crypto.hash_init()
    |> :crypto.hash_update(value)
    |> :crypto.hash_update(config()[:pk_hash_salt])
    |> :crypto.hash_final()
    |> Base.encode16()
  end

  def get_by_id(id) do
    Mongo.find_one(@collection, %{"_id" => id})
  end

  def produce_create_episode(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:episode_create, Map.drop(params, ~w(patient_id patient_id_hash))),
         {:ok, job, episode_create_job} <-
           Jobs.create(
             EpisodeCreateJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_create_job) do
      {:ok, job}
    end
  end

  def produce_update_episode(
        %{"patient_id_hash" => patient_id_hash, "id" => id} = url_params,
        request_params,
        conn_params
      ) do
    with %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, _} <- Episodes.get(patient_id_hash, id),
         :ok <- JsonSchema.validate(:episode_update, request_params),
         {:ok, job, episode_update_job} <-
           Jobs.create(
             EpisodeUpdateJob,
             url_params |> Map.merge(conn_params) |> Map.put("request_params", request_params)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_update_job) do
      {:ok, job}
    end
  end

  def produce_close_episode(
        %{"patient_id_hash" => patient_id_hash, "id" => id} = url_params,
        request_params,
        conn_params
      ) do
    with %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, _} <- Episodes.get(patient_id_hash, id),
         :ok <- JsonSchema.validate(:episode_close, request_params),
         {:ok, job, episode_close_job} <-
           Jobs.create(
             EpisodeCloseJob,
             url_params |> Map.merge(conn_params) |> Map.put("request_params", request_params)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_close_job) do
      {:ok, job}
    end
  end

  def produce_cancel_episode(
        %{"patient_id_hash" => patient_id_hash, "id" => id} = url_params,
        request_params,
        conn_params
      ) do
    with %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, _} <- Episodes.get(patient_id_hash, id),
         :ok <- JsonSchema.validate(:episode_cancel, request_params),
         {:ok, job, episode_cancel_job} <-
           Jobs.create(
             EpisodeCancelJob,
             url_params |> Map.merge(conn_params) |> Map.put("request_params", request_params)
           ),
         :ok <- @kafka_producer.publish_medical_event(episode_cancel_job) do
      {:ok, job}
    end
  end

  def produce_create_package(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:package_create, Map.drop(params, ~w(patient_id patient_id_hash))),
         {:ok, job, package_create_job} <-
           Jobs.create(
             PackageCreateJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(package_create_job) do
      {:ok, job}
    end
  end

  def produce_cancel_package(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with :ok <- JsonSchema.validate(:package_cancel, Map.take(params, ["signed_data"])),
         %{} = patient <- get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, %{"data" => signed_data_decoded}} <- @digital_signature.decode(params["signed_data"], []),
         {:ok, %{"content" => decoded_content, "signer" => signer}} <- Signature.validate(signed_data_decoded),
         :ok <- JsonSchema.validate(:package_cancel_signed_content, decoded_content),
         employee_id <- get_in(decoded_content, ["encounter", "performer", "identifier", "value"]),
         :ok <- Signature.check_drfo(signer, employee_id) do
      job_data =
        params
        |> Map.put("user_id", user_id)
        |> Map.put("client_id", client_id)

      with {:ok, job, package_cancel_job} <- Jobs.create(PackageCancelJob, job_data),
           :ok <- @kafka_producer.publish_medical_event(package_cancel_job) do
        {:ok, job}
      end
    end
  end

  def consume_cancel_package(%PackageCancelJob{patient_id_hash: patient_id_hash, user_id: user_id} = job) do
    with {:ok, %{"data" => data}} <- @digital_signature.decode(job.signed_data, []),
         {:ok, %{"content" => decoded_content, "signer" => _signer}} <- Signature.validate(data),
         :ok <- JsonSchema.validate(:package_cancel_signed_content, decoded_content),
         encounter_id <- decoded_content["encounter"]["id"],
         {_, %{} = patient} <- {:patient, get_by_id(patient_id_hash)},
         {_, {:ok, %Encounter{} = encounter}} <- {:encounter, Encounters.get_by_id(patient_id_hash, encounter_id)},
         :ok <- CancelEncounter.validate_cancellation(decoded_content, encounter, patient_id_hash),
         :ok <- CancelEncounter.proccess_cancellation(patient, user_id, decoded_content) do
      {:ok, %{}, 200}
    else
      {:patient, _} -> {:ok, "Failed to get patient", 404}
      {:encounter, _} -> {:ok, "Failed to get encounter", 404}
      err -> err
    end
  end

  def consume_create_package(
        %PackageCreateJob{patient_id: patient_id, patient_id_hash: patient_id_hash, user_id: user_id} = job
      ) do
    now = DateTime.utc_now()

    with {:ok, %{"data" => data}} <- @digital_signature.decode(job.signed_data, []),
         {:ok, %{"content" => content, "signer" => _signer}} <- Signature.validate(data),
         :ok <- JsonSchema.validate(:package_create_signed_content, content) do
      with {:ok, visit} <- create_visit(job),
           {:ok, observations} <- create_observations(job, content),
           {:ok, conditions} <- create_conditions(job, content, observations),
           {:ok, encounter} <- create_encounter(job, content, conditions, visit),
           {:ok, immunizations} <- create_immunizations(job, content, observations),
           {:ok, allergy_intolerances} <- create_allergy_intolerances(job, content) do
        visit_id = if is_map(visit), do: visit.id
        encounter = Encounters.fill_up_encounter_performer(encounter)
        resource_name = "#{encounter.id}/create"
        files = [{'signed_content.txt', job.signed_data}]
        {:ok, {_, compressed_content}} = :zip.create("signed_content.zip", files, [:memory])

        with {:ok, _url} <-
               @media_storage.save(
                 patient_id,
                 compressed_content,
                 Confex.fetch_env!(:core, Core.Microservices.MediaStorage)[:encounter_bucket],
                 resource_name
               ) do
          encounter = %{encounter | signed_content_links: [resource_name]}

          set =
            %{"updated_by" => user_id, "updated_at" => now}
            |> Mongo.add_to_set(visit, "visits.#{visit_id}")
            |> Mongo.add_to_set(encounter, "encounters.#{encounter.id}")
            |> Mongo.convert_to_uuid("visits.#{visit_id}.id")
            |> Mongo.convert_to_uuid("visits.#{visit_id}.inserted_by")
            |> Mongo.convert_to_uuid("visits.#{visit_id}.updated_by")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.id")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.inserted_by")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.updated_by")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.division.identifier.value")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.episode.identifier.value")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.performer.identifier.value")
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.visit.identifier.value")
            |> Mongo.convert_to_uuid(
              "encounters.#{encounter.id}.diagnoses",
              ~w(condition identifier value)a
            )
            |> Mongo.convert_to_uuid(
              "encounters.#{encounter.id}.incoming_referrals",
              ~w(identifier value)a
            )
            |> Mongo.convert_to_uuid("encounters.#{encounter.id}.service_provider.identifier.value")
            |> Mongo.convert_to_uuid("updated_by")

          diagnoses_history =
            DiagnosesHistory.create(%{
              "date" => DateTime.utc_now(),
              "evidence" => %{
                "identifier" => %{
                  "type" => %{
                    "coding" => [
                      %{
                        "system" => "eHealth/resources",
                        "code" => "encounter"
                      }
                    ]
                  },
                  "value" => Mongo.string_to_uuid(encounter.id)
                }
              },
              "is_active" => true
            })

          diagnoses_history = %{
            diagnoses_history
            | diagnoses:
                Enum.map(encounter.diagnoses, fn diagnosis ->
                  condition = diagnosis.condition

                  %{
                    diagnosis
                    | condition: %{
                        condition
                        | identifier: %{
                            condition.identifier
                            | value: Mongo.string_to_uuid(condition.identifier.value)
                          }
                      }
                  }
                end)
          }

          push =
            Mongo.add_to_push(
              %{},
              diagnoses_history,
              "episodes.#{encounter.episode.identifier.value}.diagnoses_history"
            )

          set =
            Enum.reduce(immunizations, set, fn immunization, acc ->
              immunization = Immunizations.fill_up_immunization_performer(immunization)

              acc
              |> Mongo.add_to_set(immunization, "immunizations.#{immunization.id}")
              |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.id")
              |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.inserted_by")
              |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.updated_by")
              |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.context.identifier.value")
              |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.legal_entity.identifier.value")
              |> Mongo.convert_to_uuid("immunizations.#{immunization.id}.source.value.identifier.value")
              |> Mongo.convert_to_uuid(
                "immunizations.#{immunization.id}.reactions",
                ~w(detail identifier value)a
              )
            end)

          set =
            Enum.reduce(allergy_intolerances, set, fn allergy_intolerance, acc ->
              allergy_intolerance = AllergyIntolerances.fill_up_allergy_intolerance_asserter(allergy_intolerance)

              acc
              |> Mongo.add_to_set(
                allergy_intolerance,
                "allergy_intolerances.#{allergy_intolerance.id}"
              )
              |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.id")
              |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.inserted_by")
              |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.updated_by")
              |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.context.identifier.value")
              |> Mongo.convert_to_uuid("allergy_intolerances.#{allergy_intolerance.id}.source.value.identifier.value")
            end)

          {:ok, %{matched_count: 1, modified_count: 1}} =
            Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{
              "$set" => set,
              "$push" => push
            })

          links = [
            %{
              "entity" => "encounter",
              "href" => "/api/patients/#{patient_id}/encounters/#{encounter.id}"
            }
          ]

          links =
            links
            |> insert_conditions(conditions, patient_id)
            |> insert_observations(observations, patient_id)

          links =
            Enum.reduce(immunizations, links, fn immunization, acc ->
              acc ++
                [
                  %{
                    "entity" => "immunization",
                    "href" => "/api/patients/#{patient_id}/immunizations/#{immunization.id}"
                  }
                ]
            end)

          links =
            Enum.reduce(allergy_intolerances, links, fn allergy_intolerance, acc ->
              acc ++
                [
                  %{
                    "entity" => "allergy_intolerance",
                    "href" => "/api/patients/#{patient_id}/allergy_intolerances/#{allergy_intolerance.id}"
                  }
                ]
            end)

          {:ok, %{"links" => links}, 200}
        else
          _ -> Logger.error("Failed to save signed content")
        end
      else
        {:error, error, status_code} ->
          {:ok, error, status_code}

        {:error, error} ->
          {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(error)}), 422}
      end
    else
      {:error, %{"error" => error, "meta" => _}} ->
        {:ok, Jason.encode!(error), 422}

      {:error, error} ->
        {:ok, ValidationError.render("422.json", %{schema: error}), 422}

      {:error, {:bad_request, error}} ->
        {:ok, error, 422}
    end
  end

  def consume_create_episode(
        %EpisodeCreateJob{patient_id: patient_id, patient_id_hash: patient_id_hash, client_id: client_id} = job
      ) do
    now = DateTime.utc_now()

    episode =
      job
      |> Map.from_struct()
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Episode.create()

    episode =
      %{
        episode
        | status_history: [],
          diagnoses_history: [],
          inserted_by: job.user_id,
          updated_by: job.user_id,
          inserted_at: now,
          updated_at: now
      }
      |> EpisodeValidations.validate_period()
      |> EpisodeValidations.validate_managing_organization(client_id)
      |> EpisodeValidations.validate_care_manager(client_id)

    episode_id = episode.id

    case Vex.errors(episode) do
      [] ->
        case Episodes.get(patient_id_hash, episode_id) do
          {:ok, _} ->
            {:ok, %{"error" => "Episode with such id already exists"}, 422}

          _ ->
            episode =
              episode
              |> Episodes.fill_up_episode_care_manager()
              |> Episodes.fill_up_episode_managing_organization()

            set =
              %{"updated_by" => episode.updated_by}
              |> Mongo.add_to_set(episode, "episodes.#{episode.id}")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.id")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.inserted_by")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.updated_by")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.care_manager.identifier.value")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.managing_organization.identifier.value")
              |> Mongo.convert_to_uuid("updated_by")

            {:ok, %{matched_count: 1, modified_count: 1}} =
              Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{"$set" => set})

            {:ok,
             %{
               "links" => [
                 %{
                   "entity" => "episode",
                   "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
                 }
               ]
             }, 200}
        end

      errors ->
        {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}), 422}
    end
  end

  def consume_update_episode(
        %EpisodeUpdateJob{patient_id: patient_id, patient_id_hash: patient_id_hash, id: id, client_id: client_id} = job
      ) do
    now = DateTime.utc_now()
    status = Episode.status(:active)

    with {:ok, %{"status" => ^status} = episode} <- Episodes.get(patient_id_hash, id) do
      changes = Map.take(job.request_params, ~w(name managing_organization care_manager))
      episode = Episode.create(episode)

      episode =
        %{episode | updated_by: job.user_id, updated_at: now}
        |> Map.merge(Enum.into(changes, %{}, fn {k, v} -> {String.to_atom(k), v} end))
        |> EpisodeValidations.validate_managing_organization(
          job.request_params["managing_organization"],
          client_id
        )
        |> EpisodeValidations.validate_care_manager(job.request_params["care_manager"], client_id)

      case Vex.errors(episode) do
        [] ->
          episode =
            episode
            |> Episodes.fill_up_episode_care_manager()
            |> Episodes.fill_up_episode_managing_organization()

          set =
            %{"updated_by" => episode.updated_by, "updated_at" => now}
            |> Mongo.add_to_set(episode.care_manager, "episodes.#{episode.id}.care_manager")
            |> Mongo.add_to_set(episode.name, "episodes.#{episode.id}.name")
            |> Mongo.add_to_set(
              episode.managing_organization,
              "episodes.#{episode.id}.managing_organization"
            )
            |> Mongo.convert_to_uuid("episodes.#{episode.id}.updated_by")
            |> Mongo.convert_to_uuid("episodes.#{episode.id}.care_manager.identifier.value")
            |> Mongo.convert_to_uuid("episodes.#{episode.id}.managing_organization.identifier.value")
            |> Mongo.convert_to_uuid("updated_by")

          {:ok, %{matched_count: 1, modified_count: 1}} =
            Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{"$set" => set})

          {:ok,
           %{
             "links" => [
               %{
                 "entity" => "episode",
                 "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
               }
             ]
           }, 200}

        errors ->
          {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}), 422}
      end
    else
      {:ok, %{"status" => status}} -> {:ok, "Episode in status #{status} can not be updated", 422}
      nil -> {:error, "Failed to get episode", 404}
    end
  end

  def consume_close_episode(%EpisodeCloseJob{patient_id: patient_id, patient_id_hash: patient_id_hash, id: id} = job) do
    now = DateTime.utc_now()
    status = Episode.status(:active)

    with {:ok, %{"status" => ^status} = episode} <- Episodes.get(patient_id_hash, id) do
      episode = Episode.create(episode)
      new_period = DatePeriod.create(job.request_params["period"])
      changes = Map.take(job.request_params, ~w(closing_summary closing_reason))

      episode =
        %{
          episode
          | status: Episode.status(:closed),
            updated_by: job.user_id,
            updated_at: now,
            period: %{episode.period | end: new_period.end}
        }
        |> Map.merge(Enum.into(changes, %{}, fn {k, v} -> {String.to_atom(k), v} end))
        |> EpisodeValidations.validate_period()

      case Vex.errors(episode) do
        [] ->
          set =
            %{"updated_by" => episode.updated_by, "updated_at" => episode.updated_at}
            |> Mongo.add_to_set(episode.status, "episodes.#{episode.id}.status")
            |> Mongo.add_to_set(episode.closing_reason, "episodes.#{episode.id}.closing_reason")
            |> Mongo.add_to_set(episode.closing_summary, "episodes.#{episode.id}.closing_summary")
            |> Mongo.add_to_set(episode.period.end, "episodes.#{episode.id}.period.end")
            |> Mongo.convert_to_uuid("updated_by")

          status_history =
            StatusHistory.create(%{
              "status" => episode.status,
              "inserted_at" => episode.updated_at,
              "inserted_by" => Mongo.string_to_uuid(episode.updated_by)
            })

          push = Mongo.add_to_push(%{}, status_history, "episodes.#{episode.id}.status_history")

          {:ok, %{matched_count: 1, modified_count: 1}} =
            Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{
              "$set" => set,
              "$push" => push
            })

          {:ok,
           %{
             "links" => [
               %{
                 "entity" => "episode",
                 "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
               }
             ]
           }, 200}

        errors ->
          {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}), 422}
      end
    else
      {:ok, %{"status" => status}} -> {:ok, "Episode in status #{status} can not be closed", 422}
      nil -> {:error, "Failed to get episode", 404}
    end
  end

  def consume_cancel_episode(%EpisodeCancelJob{patient_id: patient_id, patient_id_hash: patient_id_hash, id: id} = job) do
    now = DateTime.utc_now()
    status = Episode.status(:active)

    with {:ok, %{"status" => ^status} = episode} <- Episodes.get(patient_id_hash, id) do
      episode = Episode.create(episode)
      changes = Map.take(job.request_params, ~w(explanatory_letter cancellation_reason))

      episode =
        %{
          episode
          | status: Episode.status(:cancelled),
            updated_by: job.user_id,
            updated_at: now
        }
        |> Map.merge(Enum.into(changes, %{}, fn {k, v} -> {String.to_atom(k), v} end))

      case Vex.errors(episode) do
        [] ->
          all_encounters_canceled =
            patient_id_hash
            |> Encounters.get_episode_encounters(Mongo.string_to_uuid(id), %{
              "status" => "$encounters.v.status"
            })
            |> Enum.map(& &1["status"])
            |> Enum.all?(fn status -> status == Encounter.status(:entered_in_error) end)

          if all_encounters_canceled do
            set =
              %{"updated_by" => episode.updated_by, "updated_at" => episode.updated_at}
              |> Mongo.add_to_set(episode.status, "episodes.#{episode.id}.status")
              |> Mongo.add_to_set(
                episode.explanatory_letter,
                "episodes.#{episode.id}.explanatory_letter"
              )
              |> Mongo.add_to_set(
                episode.cancellation_reason,
                "episodes.#{episode.id}.cancellation_reason"
              )
              |> Mongo.convert_to_uuid("updated_by")

            status_history =
              StatusHistory.create(%{
                "status" => episode.status,
                "inserted_at" => episode.updated_at,
                "inserted_by" => Mongo.string_to_uuid(episode.updated_by)
              })

            push = Mongo.add_to_push(%{}, status_history, "episodes.#{episode.id}.status_history")

            {:ok, %{matched_count: 1, modified_count: 1}} =
              Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{
                "$set" => set,
                "$push" => push
              })

            {:ok,
             %{
               "links" => [
                 %{
                   "entity" => "episode",
                   "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
                 }
               ]
             }, 200}
          else
            {:error, "Episode can not be canceled while it has not canceled encounters", 409}
          end

        errors ->
          {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}), 422}
      end
    else
      {:ok, %{"status" => status}} ->
        {:ok, "Episode in status #{status} can not be canceled", 422}

      nil ->
        {:error, "Failed to get episode", 404}
    end
  end

  defp create_visit(%PackageCreateJob{visit: nil}), do: {:ok, nil}

  defp create_visit(%PackageCreateJob{patient_id_hash: patient_id_hash, user_id: user_id, visit: visit}) do
    now = DateTime.utc_now()
    visit = Visit.create(visit)

    visit =
      %{visit | inserted_by: user_id, updated_by: user_id, inserted_at: now, updated_at: now}
      |> VisitValidations.validate_period()

    case Vex.errors(%{visit: visit}, visit: [reference: [path: "visit"]]) do
      [] ->
        result =
          Patient.metadata().collection
          |> Mongo.aggregate([
            %{"$match" => %{"_id" => patient_id_hash}},
            %{"$project" => %{"_id" => "$visits.#{visit.id}.id"}}
          ])
          |> Enum.to_list()

        case result do
          [%{"_id" => _}] ->
            {:error, "Visit with such id already exists", 409}

          _ ->
            {:ok, visit}
        end

      errors ->
        {:error, errors}
    end
  end

  defp create_encounter(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         content,
         conditions,
         visit
       ) do
    now = DateTime.utc_now()
    encounter = Encounter.create(content["encounter"])

    encounter =
      %{
        encounter
        | inserted_by: user_id,
          updated_by: user_id,
          inserted_at: now,
          updated_at: now
      }
      |> EncounterValidations.validate_episode(patient_id_hash)
      |> EncounterValidations.validate_visit(visit, patient_id_hash)
      |> EncounterValidations.validate_performer(client_id)
      |> EncounterValidations.validate_division(client_id)
      |> EncounterValidations.validate_diagnoses(conditions, patient_id_hash)
      |> EncounterValidations.validate_date()

    case Vex.errors(%{encounter: encounter}, encounter: [reference: [path: "encounter"]]) do
      [] ->
        result =
          Patient.metadata().collection
          |> Mongo.aggregate([
            %{"$match" => %{"_id" => patient_id_hash}},
            %{"$project" => %{"_id" => "$encounters.#{encounter.id}.id"}}
          ])
          |> Enum.to_list()

        case result do
          [%{"_id" => _}] ->
            {:error, "Encounter with such id already exists", 409}

          _ ->
            {:ok, encounter}
        end

      errors ->
        {:error, errors}
    end
  end

  defp create_conditions(
         %PackageCreateJob{
           patient_id_hash: patient_id_hash,
           user_id: user_id,
           client_id: client_id
         },
         %{"conditions" => _} = content,
         observations
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    conditions =
      Enum.map(content["conditions"], fn data ->
        condition = Condition.create(data)

        %{
          condition
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id,
            patient_id: patient_id_hash
        }
        |> ConditionValidations.validate_onset_date()
        |> ConditionValidations.validate_context(encounter_id)
        |> ConditionValidations.validate_evidences(observations, patient_id_hash)
        |> ConditionValidations.validate_source(client_id)
      end)

    case Vex.errors(
           %{conditions: conditions},
           conditions: [unique_ids: [field: :_id], reference: [path: "conditions"]]
         ) do
      [] ->
        validate_conditions(conditions)

      errors ->
        {:error, errors}
    end
  end

  defp create_conditions(_, _, _), do: {:ok, []}

  defp create_observations(
         %PackageCreateJob{patient_id_hash: patient_id_hash, user_id: user_id, client_id: client_id},
         %{"observations" => _} = content
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    observations =
      Enum.map(content["observations"], fn data ->
        observation = Observation.create(data)

        %{
          observation
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id,
            patient_id: patient_id_hash
        }
        |> ObservationValidations.validate_issued()
        |> ObservationValidations.validate_effective_at()
        |> ObservationValidations.validate_context(encounter_id)
        |> ObservationValidations.validate_source(client_id)
        |> ObservationValidations.validate_value()
        |> ObservationValidations.validate_components()
      end)

    case Vex.errors(
           %{observations: observations},
           observations: [unique_ids: [field: :_id], reference: [path: "observations"]]
         ) do
      [] ->
        validate_observations(observations)

      errors ->
        {:error, errors}
    end
  end

  defp create_observations(_, _), do: {:ok, []}

  defp create_immunizations(
         %PackageCreateJob{patient_id_hash: patient_id_hash, user_id: user_id, client_id: client_id},
         %{"immunizations" => _} = content,
         observations
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    immunizations =
      Enum.map(content["immunizations"], fn data ->
        immunization = Immunization.create(data)

        %{
          immunization
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id
        }
        |> ImmunizationValidations.validate_date()
        |> ImmunizationValidations.validate_context(encounter_id)
        |> ImmunizationValidations.validate_source(client_id)
        |> ImmunizationValidations.validate_reactions(observations, patient_id_hash)
      end)

    case Vex.errors(
           %{immunizations: immunizations},
           immunizations: [unique_ids: [field: :id], reference: [path: "immunizations"]]
         ) do
      [] ->
        validate_immunizations(patient_id_hash, immunizations)

      errors ->
        {:error, errors}
    end
  end

  defp create_immunizations(_, _, _), do: {:ok, []}

  defp create_allergy_intolerances(
         %PackageCreateJob{patient_id_hash: patient_id_hash, user_id: user_id, client_id: client_id},
         %{"allergy_intolerances" => _} = content
       ) do
    now = DateTime.utc_now()
    encounter_id = content["encounter"]["id"]

    allergy_intolerances =
      Enum.map(content["allergy_intolerances"], fn data ->
        allergy_intolerance = AllergyIntolerance.create(data)

        %{
          allergy_intolerance
          | inserted_at: now,
            updated_at: now,
            inserted_by: user_id,
            updated_by: user_id
        }
        |> AllergyIntoleranceValidations.validate_context(encounter_id)
        |> AllergyIntoleranceValidations.validate_source(client_id)
        |> AllergyIntoleranceValidations.validate_onset_date_time()
        |> AllergyIntoleranceValidations.validate_last_occurence()
        |> AllergyIntoleranceValidations.validate_asserted_date()
      end)

    case Vex.errors(
           %{allergy_intolerances: allergy_intolerances},
           allergy_intolerances: [
             unique_ids: [field: :id],
             reference: [path: "allergy_intolerances"]
           ]
         ) do
      [] ->
        validate_allergy_intolerances(patient_id_hash, allergy_intolerances)

      errors ->
        {:error, errors}
    end
  end

  defp create_allergy_intolerances(_, _), do: {:ok, []}

  defp validate_conditions(conditions) do
    Enum.reduce_while(conditions, {:ok, conditions}, fn condition, acc ->
      if Mongo.find_one(Condition.metadata().collection, %{"_id" => condition._id}, projection: %{"_id" => true}) do
        {:halt, {:error, "Condition with id '#{condition._id}' already exists", 409}}
      else
        {:cont, acc}
      end
    end)
  end

  defp validate_observations(observations) do
    Enum.reduce_while(observations, {:ok, observations}, fn observation, acc ->
      if Mongo.find_one(
           Observation.metadata().collection,
           %{"_id" => Mongo.string_to_uuid(observation._id)},
           projection: %{"_id" => true}
         ) do
        {:halt, {:error, "Observation with id '#{observation._id}' already exists", 409}}
      else
        {:cont, acc}
      end
    end)
  end

  defp validate_immunizations(patient_id_hash, immunizations) do
    Enum.reduce_while(immunizations, {:ok, immunizations}, fn immunization, acc ->
      case Immunizations.get(patient_id_hash, immunization.id) do
        {:ok, _} ->
          {:halt, {:error, "Immunization with id '#{immunization.id}' already exists", 409}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp validate_allergy_intolerances(patient_id_hash, allergy_intolerances) do
    Enum.reduce_while(allergy_intolerances, {:ok, allergy_intolerances}, fn allergy_intolerance, acc ->
      case AllergyIntolerances.get(patient_id_hash, allergy_intolerance.id) do
        {:ok, _} ->
          {:halt, {:error, "Allergy intolerance with id '#{allergy_intolerance.id}' already exists", 409}}

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp insert_conditions(links, [], _), do: links

  defp insert_conditions(links, conditions, patient_id) do
    conditions = Enum.map(conditions, &Conditions.create/1)

    {:ok, %{inserted_ids: condition_ids}} = Mongo.insert_many(Condition.metadata().collection, conditions, [])

    Enum.reduce(condition_ids, links, fn {_, condition_id}, acc ->
      acc ++
        [
          %{
            "entity" => "condition",
            "href" => "/api/patients/#{patient_id}/conditions/#{condition_id}"
          }
        ]
    end)
  end

  defp insert_observations(links, [], _), do: links

  defp insert_observations(links, observations, patient_id) do
    observations = Enum.map(observations, &Observations.create/1)

    {:ok, %{inserted_ids: observation_ids}} = Mongo.insert_many(Observation.metadata().collection, observations, [])

    Enum.reduce(observation_ids, links, fn {_, observation_id}, acc ->
      acc ++
        [
          %{
            "entity" => "observation",
            "href" => "/api/patients/#{patient_id}/observations/#{observation_id}"
          }
        ]
    end)
  end
end
