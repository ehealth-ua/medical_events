defmodule Api.Rpc do
  @moduledoc """
  This module contains functions that are called from other pods via RPC.
  """

  alias Api.Web.ApprovalView
  alias Api.Web.EpisodeView
  alias Core.Approval
  alias Core.Approvals
  alias Core.Conditions
  alias Core.Observations
  alias Core.Patients
  alias Core.Patients.AllergyIntolerances
  alias Core.Patients.Encounters
  alias Core.Patients.Episodes
  alias Core.Patients.Immunizations

  @status_active Approval.status(:active)

  @type approval() :: %{
          access_level: binary(),
          granted_by: reference_(),
          granted_resources: list(reference_()),
          granted_to: reference_(),
          id: binary(),
          inserted_at: DateTime,
          reason: nil | reference_(),
          status: binary(),
          updated_at: DateTime,
          urgent: map()
        }

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

  @doc """
  Get episode by patient id, encounter id

  ## Examples

      iex> Api.Rpc.episode_by_encounter_id(
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
            value: "1857c60a-cbc5-4244-9a31-9dd310828346"
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
                value: "9547dfe3-7830-470e-a95a-4c046e59fd46"
              }
            },
            rank: 930,
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
                value: "aa456b10-141f-4e88-a7a2-f41cae4b8b50"
              }
            },
            rank: 890,
            role: %{
              coding: [%{code: "primary", system: "eHealth/diagnosis_roles"}],
              text: "code text"
            }
          }
        ],
        diagnoses_history: [
          %{
            date: ~D[2019-02-04],
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
                    value: "9547dfe3-7830-470e-a95a-4c046e59fd46"
                  }
                },
                rank: 930,
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
                    value: "aa456b10-141f-4e88-a7a2-f41cae4b8b50"
                  }
                },
                rank: 890,
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
                value: "30c96863-6579-47ee-9811-a6ec45ed0914"
              }
            },
            is_active: true
          }
        ],
        explanatory_letter: "explanatory letter",
        id: "4d5d59bb-9341-449b-905a-bd1aef84c68f",
        inserted_at: #DateTime<2019-02-04 13:29:00.630Z>,
        managing_organization: %{
          display_value: nil,
          identifier: %{
            type: %{
              coding: [%{code: "legal_entity", system: "eHealth/resources"}],
              text: "code text"
            },
            value: "8264b816-5d74-4039-a68d-3b486f48c4b1"
          }
        },
        name: "ОРВИ 2018",
        period: %{end: "2019-02-04", start: "2019-02-04"},
        referral_requests: [
          %{
            display_value: nil,
            identifier: %{
              type: %{
                coding: [%{code: "service_request", system: "eHealth/resources"}],
                text: "code text"
              },
              value: "1a403ff8-9ccb-433e-8a5f-b3e252ee3b8c"
            }
          }
        ],
        status: "active",
        status_history: [
          %{
            inserted_at: "2019-02-04T13:29:00.630Z",
            inserted_by: "c056e131-433e-462b-a1d6-d35e75ff6106",
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
        updated_at: #DateTime<2019-02-04 13:29:00.630Z>
      }}
  """
  @spec episode_by_encounter_id(patient_id :: binary(), encounter_id :: binary()) :: nil | {:ok, episode}
  def episode_by_encounter_id(patient_id, encounter_id) do
    patient_id_hash = Patients.get_pk_hash(patient_id)

    with {:ok, encounter} <- Encounters.get_by_id(patient_id_hash, encounter_id),
         {:ok, episode} <- Episodes.get_by_id(patient_id_hash, to_string(encounter.episode.identifier.value)) do
      {:ok, EpisodeView.render("show.json", %{episode: episode})}
    end
  end

  @doc """
  Get episode by patient id, observation id

  ## Examples

      iex> Api.Rpc.episode_by_observation_id(
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
            value: "1857c60a-cbc5-4244-9a31-9dd310828346"
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
                value: "9547dfe3-7830-470e-a95a-4c046e59fd46"
              }
            },
            rank: 930,
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
                value: "aa456b10-141f-4e88-a7a2-f41cae4b8b50"
              }
            },
            rank: 890,
            role: %{
              coding: [%{code: "primary", system: "eHealth/diagnosis_roles"}],
              text: "code text"
            }
          }
        ],
        diagnoses_history: [
          %{
            date: ~D[2019-02-04],
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
                    value: "9547dfe3-7830-470e-a95a-4c046e59fd46"
                  }
                },
                rank: 930,
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
                    value: "aa456b10-141f-4e88-a7a2-f41cae4b8b50"
                  }
                },
                rank: 890,
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
                value: "30c96863-6579-47ee-9811-a6ec45ed0914"
              }
            },
            is_active: true
          }
        ],
        explanatory_letter: "explanatory letter",
        id: "4d5d59bb-9341-449b-905a-bd1aef84c68f",
        inserted_at: #DateTime<2019-02-04 13:29:00.630Z>,
        managing_organization: %{
          display_value: nil,
          identifier: %{
            type: %{
              coding: [%{code: "legal_entity", system: "eHealth/resources"}],
              text: "code text"
            },
            value: "8264b816-5d74-4039-a68d-3b486f48c4b1"
          }
        },
        name: "ОРВИ 2018",
        period: %{end: "2019-02-04", start: "2019-02-04"},
        referral_requests: [
          %{
            display_value: nil,
            identifier: %{
              type: %{
                coding: [%{code: "service_request", system: "eHealth/resources"}],
                text: "code text"
              },
              value: "1a403ff8-9ccb-433e-8a5f-b3e252ee3b8c"
            }
          }
        ],
        status: "active",
        status_history: [
          %{
            inserted_at: "2019-02-04T13:29:00.630Z",
            inserted_by: "c056e131-433e-462b-a1d6-d35e75ff6106",
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
        updated_at: #DateTime<2019-02-04 13:29:00.630Z>
      }}
  """
  @spec episode_by_observation_id(patient_id :: binary(), observation_id :: binary()) :: nil | {:ok, episode}
  def episode_by_observation_id(patient_id, observation_id) do
    patient_id_hash = Patients.get_pk_hash(patient_id)

    with {:ok, observation} <- Observations.get_by_id(patient_id_hash, observation_id),
         {:ok, encounter} <- Encounters.get_by_id(patient_id_hash, to_string(observation.context.identifier.value)),
         {:ok, episode} <- Episodes.get_by_id(patient_id_hash, to_string(encounter.episode.identifier.value)) do
      {:ok, EpisodeView.render("show.json", %{episode: episode})}
    end
  end

  @doc """
  Get episode by patient id, condition id

  ## Examples

      iex> Api.Rpc.episode_by_condition_id(
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
            value: "1857c60a-cbc5-4244-9a31-9dd310828346"
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
                value: "9547dfe3-7830-470e-a95a-4c046e59fd46"
              }
            },
            rank: 930,
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
                value: "aa456b10-141f-4e88-a7a2-f41cae4b8b50"
              }
            },
            rank: 890,
            role: %{
              coding: [%{code: "primary", system: "eHealth/diagnosis_roles"}],
              text: "code text"
            }
          }
        ],
        diagnoses_history: [
          %{
            date: ~D[2019-02-04],
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
                    value: "9547dfe3-7830-470e-a95a-4c046e59fd46"
                  }
                },
                rank: 930,
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
                    value: "aa456b10-141f-4e88-a7a2-f41cae4b8b50"
                  }
                },
                rank: 890,
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
                value: "30c96863-6579-47ee-9811-a6ec45ed0914"
              }
            },
            is_active: true
          }
        ],
        explanatory_letter: "explanatory letter",
        id: "4d5d59bb-9341-449b-905a-bd1aef84c68f",
        inserted_at: #DateTime<2019-02-04 13:29:00.630Z>,
        managing_organization: %{
          display_value: nil,
          identifier: %{
            type: %{
              coding: [%{code: "legal_entity", system: "eHealth/resources"}],
              text: "code text"
            },
            value: "8264b816-5d74-4039-a68d-3b486f48c4b1"
          }
        },
        name: "ОРВИ 2018",
        period: %{end: "2019-02-04", start: "2019-02-04"},
        referral_requests: [
          %{
            display_value: nil,
            identifier: %{
              type: %{
                coding: [%{code: "service_request", system: "eHealth/resources"}],
                text: "code text"
              },
              value: "1a403ff8-9ccb-433e-8a5f-b3e252ee3b8c"
            }
          }
        ],
        status: "active",
        status_history: [
          %{
            inserted_at: "2019-02-04T13:29:00.630Z",
            inserted_by: "c056e131-433e-462b-a1d6-d35e75ff6106",
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
        updated_at: #DateTime<2019-02-04 13:29:00.630Z>
      }}
  """
  @spec episode_by_condition_id(patient_id :: binary(), condition_id :: binary()) :: nil | {:ok, episode}
  def episode_by_condition_id(patient_id, condition_id) do
    patient_id_hash = Patients.get_pk_hash(patient_id)

    with {:ok, condition} <- Conditions.get_by_id(patient_id_hash, condition_id),
         {:ok, encounter} <- Encounters.get_by_id(patient_id_hash, to_string(condition.context.identifier.value)),
         {:ok, episode} <- Episodes.get_by_id(patient_id_hash, to_string(encounter.episode.identifier.value)) do
      {:ok, EpisodeView.render("show.json", %{episode: episode})}
    end
  end

  @doc """
  Get episode by patient id, allergy intolerance id

  ## Examples

      iex> Api.Rpc.episode_by_allergy_intolerance_id(
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
            value: "1857c60a-cbc5-4244-9a31-9dd310828346"
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
                value: "9547dfe3-7830-470e-a95a-4c046e59fd46"
              }
            },
            rank: 930,
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
                value: "aa456b10-141f-4e88-a7a2-f41cae4b8b50"
              }
            },
            rank: 890,
            role: %{
              coding: [%{code: "primary", system: "eHealth/diagnosis_roles"}],
              text: "code text"
            }
          }
        ],
        diagnoses_history: [
          %{
            date: ~D[2019-02-04],
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
                    value: "9547dfe3-7830-470e-a95a-4c046e59fd46"
                  }
                },
                rank: 930,
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
                    value: "aa456b10-141f-4e88-a7a2-f41cae4b8b50"
                  }
                },
                rank: 890,
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
                value: "30c96863-6579-47ee-9811-a6ec45ed0914"
              }
            },
            is_active: true
          }
        ],
        explanatory_letter: "explanatory letter",
        id: "4d5d59bb-9341-449b-905a-bd1aef84c68f",
        inserted_at: #DateTime<2019-02-04 13:29:00.630Z>,
        managing_organization: %{
          display_value: nil,
          identifier: %{
            type: %{
              coding: [%{code: "legal_entity", system: "eHealth/resources"}],
              text: "code text"
            },
            value: "8264b816-5d74-4039-a68d-3b486f48c4b1"
          }
        },
        name: "ОРВИ 2018",
        period: %{end: "2019-02-04", start: "2019-02-04"},
        referral_requests: [
          %{
            display_value: nil,
            identifier: %{
              type: %{
                coding: [%{code: "service_request", system: "eHealth/resources"}],
                text: "code text"
              },
              value: "1a403ff8-9ccb-433e-8a5f-b3e252ee3b8c"
            }
          }
        ],
        status: "active",
        status_history: [
          %{
            inserted_at: "2019-02-04T13:29:00.630Z",
            inserted_by: "c056e131-433e-462b-a1d6-d35e75ff6106",
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
        updated_at: #DateTime<2019-02-04 13:29:00.630Z>
      }}
  """
  @spec episode_by_allergy_intolerance_id(
          patient_id :: binary(),
          allergy_intolerance_id :: binary()
        ) :: nil | {:ok, episode}
  def episode_by_allergy_intolerance_id(patient_id, allergy_intolerance_id) do
    patient_id_hash = Patients.get_pk_hash(patient_id)

    with {:ok, allergy_intolerance} <- AllergyIntolerances.get_by_id(patient_id_hash, allergy_intolerance_id),
         {:ok, encounter} <-
           Encounters.get_by_id(patient_id_hash, to_string(allergy_intolerance.context.identifier.value)),
         {:ok, episode} <- Episodes.get_by_id(patient_id_hash, to_string(encounter.episode.identifier.value)) do
      {:ok, EpisodeView.render("show.json", %{episode: episode})}
    end
  end

  @doc """
  Get episode by patient id, immunization id

  ## Examples

      iex> Api.Rpc.episode_by_immunization_id(
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
            value: "1857c60a-cbc5-4244-9a31-9dd310828346"
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
                value: "9547dfe3-7830-470e-a95a-4c046e59fd46"
              }
            },
            rank: 930,
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
                value: "aa456b10-141f-4e88-a7a2-f41cae4b8b50"
              }
            },
            rank: 890,
            role: %{
              coding: [%{code: "primary", system: "eHealth/diagnosis_roles"}],
              text: "code text"
            }
          }
        ],
        diagnoses_history: [
          %{
            date: ~D[2019-02-04],
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
                    value: "9547dfe3-7830-470e-a95a-4c046e59fd46"
                  }
                },
                rank: 930,
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
                    value: "aa456b10-141f-4e88-a7a2-f41cae4b8b50"
                  }
                },
                rank: 890,
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
                value: "30c96863-6579-47ee-9811-a6ec45ed0914"
              }
            },
            is_active: true
          }
        ],
        explanatory_letter: "explanatory letter",
        id: "4d5d59bb-9341-449b-905a-bd1aef84c68f",
        inserted_at: #DateTime<2019-02-04 13:29:00.630Z>,
        managing_organization: %{
          display_value: nil,
          identifier: %{
            type: %{
              coding: [%{code: "legal_entity", system: "eHealth/resources"}],
              text: "code text"
            },
            value: "8264b816-5d74-4039-a68d-3b486f48c4b1"
          }
        },
        name: "ОРВИ 2018",
        period: %{end: "2019-02-04", start: "2019-02-04"},
        referral_requests: [
          %{
            display_value: nil,
            identifier: %{
              type: %{
                coding: [%{code: "service_request", system: "eHealth/resources"}],
                text: "code text"
              },
              value: "1a403ff8-9ccb-433e-8a5f-b3e252ee3b8c"
            }
          }
        ],
        status: "active",
        status_history: [
          %{
            inserted_at: "2019-02-04T13:29:00.630Z",
            inserted_by: "c056e131-433e-462b-a1d6-d35e75ff6106",
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
        updated_at: #DateTime<2019-02-04 13:29:00.630Z>
      }}
  """
  @spec episode_by_immunization_id(
          patient_id :: binary(),
          immunization_id :: binary()
        ) :: nil | {:ok, episode}
  def episode_by_immunization_id(patient_id, immunization_id) do
    patient_id_hash = Patients.get_pk_hash(patient_id)

    with {:ok, immunization} <- Immunizations.get_by_id(patient_id_hash, immunization_id),
         {:ok, encounter} <- Encounters.get_by_id(patient_id_hash, to_string(immunization.context.identifier.value)),
         {:ok, episode} <- Episodes.get_by_id(patient_id_hash, to_string(encounter.episode.identifier.value)) do
      {:ok, EpisodeView.render("show.json", %{episode: episode})}
    end
  end

  @doc """
  Get approvals by patient id, employee ids, eipsode id

  ## Examples

      iex> Api.Rpc.approvals_by_episode(
        "26e673e1-1d68-413e-b96c-407b45d9f572",
        ["79707880-e3f6-471a-b6bf-e19725ad749e"],
        "d221d7f1-81cb-44d3-b6d4-8d7e42f97ff9"
      )
      [
        %{
          access_level: "read",
          granted_by: %{
            display_value: nil,
            identifier: %{
              type: %{
                coding: [%{code: "mpi-hash", system: "eHealth/resources"}],
                text: "code text"
              },
              value: "32f74603-9d19-4ebc-aea6-08668d766e38"
            }
          },
          granted_resources: [
            %{
              display_value: nil,
              identifier: %{
                type: %{
                  coding: [%{code: "episode_of_care", system: "eHealth/resources"}],
                  text: "code text"
                },
                value: "34ad80db-77cb-48c4-aacb-ade41aa7fcfc"
              }
            }
          ],
          granted_to: %{
            display_value: nil,
            identifier: %{
              type: %{
                coding: [%{code: "employee", system: "eHealth/resources"}],
                text: "code text"
              },
              value: "4a3386ff-ccfe-41e8-8e77-55147c41aa15"
            }
          },
          id: "196ccb6f-0195-4bf2-b639-800292b1ba10",
          inserted_at: #DateTime<2019-02-04 09:09:25.070Z>,
          reason: nil,
          status: "new",
          updated_at: #DateTime<2019-02-04 09:09:25.070Z>,
          urgent: %{
            "authentication_method_current" => %{
              "number" => "+38093*****85",
              "type" => "OTP"
            }
          }
        }
      ]
  """
  @spec approvals_by_episode(
          patient_id :: binary(),
          employee_ids :: list(binary),
          episode_id :: binary(),
          status :: binary()
        ) :: list(approval)
  def approvals_by_episode(patient_id, employee_ids, episode_id, status \\ @status_active) do
    approvals = Approvals.get_by_patient_id_granted_to_episode_id_status(patient_id, employee_ids, episode_id, status)
    ApprovalView.render("index.json", %{approvals: approvals})
  end
end
