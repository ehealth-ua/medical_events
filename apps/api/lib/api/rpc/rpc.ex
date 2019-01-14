defmodule Api.Rpc do
  @moduledoc """
  This module contains functions that are called from other pods via RPC.
  """

  alias Api.Web.EpisodeView
  alias Core.Patients
  alias Core.Patients.Encounters
  alias Core.Patients.Episodes

  @type coding() :: %{
          system: binary(),
          code: binary()
        }

  @type codeable_concept() :: %{
          coding: list(coding),
          text: binary()
        }

  @type diagnosis() :: %{
          code: codeable_concept(),
          condition: reference_(),
          rank: integer(),
          role: coding()
        }

  @type evidence() :: %{
          codes: list(codeable_concept()),
          details: list(reference_())
        }

  @type diagnoses_history() :: %{
          date: Date,
          diagnoses: list(diagnosis),
          evidence: evidence(),
          is_active: boolean()
        }

  @type identifier_() :: %{
          type: map(),
          value: binary()
        }

  @type reference_() :: %{
          display_value: nil | binary(),
          identifier: identifier_()
        }

  @type period() :: %{
          start: binary(),
          end: binary()
        }

  @type status_history() :: %{
          status: binary(),
          status_reason: codeable_concept(),
          inserted_at: binary(),
          inserted_by: binary()
        }

  @type episode() :: %{
          care_manager: reference_(),
          closing_summary: binary(),
          current_diagnoses: list(diagnosis),
          diagnoses_history: list(diagnoses_history),
          explanator_letter: binary(),
          id: binary(),
          inserted_at: DateTime,
          managing_organization: reference_(),
          name: binary(),
          period: period(),
          status: binary(),
          status_history: list(status_history()),
          status_reason: codeable_concept(),
          type: coding(),
          updated_at: DateTime
        }

  @doc """
  Get encounter status by patient id, encounter id

  ## Examples

      iex> Api.Rpc.encounter_status_by_id(
        "26e673e1-1d68-413e-b96c-407b45d9f572",
        "d221d7f1-81cb-44d3-b6d4-8d7e42f97ff9"
      )
      {:ok, "finished"}
  """
  @spec encounter_status_by_id(patient_id :: binary(), encounter_id :: binary()) :: nil | {:ok, binary}
  def encounter_status_by_id(patient_id, encounter_id) do
    patient_id
    |> Patients.get_pk_hash()
    |> Encounters.get_status_by_id(encounter_id)
  end

  @doc """
  Get episode by patient id, episode id

  ## Examples

      iex> Api.Rpc.episode_by_id(
        "26e673e1-1d68-413e-b96c-407b45d9f572",
        "d221d7f1-81cb-44d3-b6d4-8d7e42f97ff9"
      )
      {:ok, %{
        care_manager: %{
          display_value: nil,
          identifier: %{
            type: %{
              coding: [%{code: "employee", system: "eHealth/resources"}],
              text: "code text"
            },
            value: "6e3db345-f493-404d-bac0-83e7ef13bd64"
          }
        },
        closing_summary: "closing summary",
        current_diagnoses: [
          %{
            code: %{
              coding: [%{code: "R80", system: "eHealth/ICPC2/condition_codes"}],
              text: "code text"
            },
            condition: %{
              display_value: nil,
              identifier: %{
                type: %{
                  coding: [%{code: "condition", system: "eHealth/resources"}],
                  text: "code text"
                },
                value: "9b319b2c-644f-45b2-b35b-e01181e053c7"
              }
            },
            rank: 554,
            role: %{
              coding: [%{code: "primary", system: "eHealth/diagnosis_roles"}],
              text: "code text"
            }
          },
          %{
            code: %{
              coding: [%{code: "R80", system: "eHealth/ICPC2/condition_codes"}],
              text: "code text"
            },
            condition: %{
              display_value: nil,
              identifier: %{
                type: %{
                  coding: [%{code: "condition", system: "eHealth/resources"}],
                  text: "code text"
                },
                value: "09576df2-a2dd-4dbe-84e6-8c875379eeed"
              }
            },
            rank: 843,
            role: %{
              coding: [%{code: "primary", system: "eHealth/diagnosis_roles"}],
              text: "code text"
            }
          }
        ],
        diagnoses_history: [
          %{
            date: ~D[2019-01-14],
            diagnoses: [
              %{
                code: %{
                  coding: [%{code: "R80", system: "eHealth/ICPC2/condition_codes"}],
                  text: "code text"
                },
                condition: %{
                  display_value: nil,
                  identifier: %{
                    type: %{
                      coding: [%{code: "condition", system: "eHealth/resources"}],
                      text: "code text"
                    },
                    value: "9b319b2c-644f-45b2-b35b-e01181e053c7"
                  }
                },
                rank: 554,
                role: %{
                  coding: [%{code: "primary", system: "eHealth/diagnosis_roles"}],
                  text: "code text"
                }
              },
              %{
                code: %{
                  coding: [%{code: "R80", system: "eHealth/ICPC2/condition_codes"}],
                  text: "code text"
                },
                condition: %{
                  display_value: nil,
                  identifier: %{
                    type: %{
                      coding: [%{code: "condition", system: "eHealth/resources"}],
                      text: "code text"
                    },
                    value: "09576df2-a2dd-4dbe-84e6-8c875379eeed"
                  }
                },
                rank: 843,
                role: %{
                  coding: [%{code: "primary", system: "eHealth/diagnosis_roles"}],
                  text: "code text"
                }
              }
            ],
            evidence: %{
              display_value: nil,
              identifier: %{
                type: %{
                  coding: [%{code: "1", system: "eHealth/resources"}],
                  text: "code text"
                },
                value: "e2e8d8ed-7c68-4721-a202-0fab733a3a00"
              }
            },
            is_active: true
          }
        ],
        explanatory_letter: "explanatory letter",
        id: "2b1479b2-aa5f-4ea4-b333-662f1236dff5",
        inserted_at: #DateTime<2019-01-14 14:29:44.167Z>,
        managing_organization: %{
          display_value: nil,
          identifier: %{
            type: %{
              coding: [%{code: "legal_entity", system: "eHealth/resources"}],
              text: "code text"
            },
            value: "79707880-e3f6-471a-b6bf-e19725ad749e"
          }
        },
        name: "ОРВИ 2018",
        period: %{end: "2019-01-14", start: "2019-01-14"},
        status: "active",
        status_history: [
          %{
            inserted_at: "2019-01-14T14:29:44.167Z",
            inserted_by: "cfaaca23-0536-42da-9f0c-055dcd32c467",
            status: "active",
            status_reason: %{
              coding: [%{code: "1", system: "eHealth/episode_closing_reasons"}],
              text: "code text"
            }
          }
        ],
        status_reason: %{
          coding: [%{code: "1", system: "eHealth/resources"}],
          text: "code text"
        },
        type: %{code: "primary_care", system: "eHealth/episode_types"},
        updated_at: #DateTime<2019-01-14 14:29:44.167Z>
      }}
  """
  @spec episode_by_id(patient_id :: binary(), episode_id :: binary()) :: nil | {:ok, episode}
  def episode_by_id(patient_id, episode_id) do
    with {:ok, episode} <-
           patient_id
           |> Patients.get_pk_hash()
           |> Episodes.get_by_id(episode_id) do
      {:ok, EpisodeView.render("show.json", %{episode: episode})}
    end
  end
end
