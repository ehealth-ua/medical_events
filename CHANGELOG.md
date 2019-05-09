# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [1.2.0](https://github.com/edenlabllc/medical_events/compare/1.2.0...1.2.0) (2019-5-9)




### Features:

* added new diagnostic report validations (#416)

* validate that service/group is active and request_allowed = true (#413)

* service requests search by code (#412)

* added json schema validation on encounters list, renamed attribute (#411)

* drop casher (#410)

* code/category validations on service request create ws (#407)

* get diagnostic_report by id rpc (#405)

* search by service request changes in episodes/encounters/dr's (#406)

* new route for service requests search, some refactoring (#403)

* service_request by id rpc (#402)

* abac rpc context functions (#401)

* encryptor module improved to use all binary data (#400)

* added requester_legal_enity field to service requests (#398)

* Service requests requisition number into hash migration fix (#399)

* added explanatory_letter and cancellation_reason to DR cancel (#397)

* added diagnostic report package cancel WS (#393)

* service request requisition number into hash#4543 (#391)

* diagnostic report could be submitted as a granted_resources on approvals (#388)

* added diagnostic report reference to observations (#386)

* Service request reference on dr#4648 (#387)

* conditions and observations get by episode id functions improved (#381)

* added diagnostic report package creation (#384)

* Approvals and job collections clean up#4144 (#378)

* added diagnostic_report reference validation where TODOs were left (#371)

* added diagnostic reports to cancel package ws (#370)

* GET routes for diagnostic reports (#365)

* added diagnostic reports to create package ws (#363)

* new episode contexts routes (#361)

* add episode context rpc functions (#359)

* medical events scheduler init (#351)

* changed permitted episodes validation in service requests (#339)

* send to manager event (#350)

* added process service request WS (#346)

* removed referral requests references from episode schema (#317)

* added complete service request WS (#343)

* used_by field changes in service requests (#337)

* One of validation#5067 (#333)

* Removed referral requests from episodes (#336)

* Added supporting info to encounter (#331)

* ehealth_logger (#345)

* add separate actions for get by id in episode context (#324)

* use abac for episode routes access (#321)

* Added summary endpoint for episodes, added search by service_request_id (#315)

* use mongo transactions (#316)

* update job via ergonode (#314)

* Custom validation for oneof json schema#5067 (#278)

* support ergonode (#309)

* phoenix 1.4 (#302)

* add service requests status history (#299)

* added :list and :show endpoints for medication statements (#296)

* add service_request priority (#297)

* Validate service request expiration (#290)

* add inserted_at, updated_at to service_request responses (#295)

* Added medication statements to cancel package ws (#294)

* add episode context routes (#293)

* created medication statement structure, added it to create package ws (#288)

* add rpc abac functions (#286)

* add approvals rpc (#282)

* Added :show and :list endpoints for devices (#281)

* Added devices to cancel package ws (#275)

* add service_request expiration date (#276)

* add service_request feedback (#266)

* cancel service_request (#263)

### Bug Fixes:

* service requests cancel/recall/autoexpiration status (#418)

* job responses redesigned (#414)

* convert code identifier value in service requests to UUID (#417)

* service requests recall/cancel schema (#409)

* diagnostic_report reference in observation, cancel rendering (#404)

* libcluster api app config removed to core app (#396)

* migrator starts lib_cluster (#395)

* service requests requisition mumber into hash migration improved (#394)

* observation context_episode_id set on nil on dr package create (#392)

* added alias for our Vex module to use instead of default (#390)

* allow in progress status in service request reference validation (#374)

* cancel encounter package render (#373)

* naming pods (#368)

* used_by_legal_entity validation in complete/process service request (#364)

* service requests services status (#362)

* logging (#360)

* Fixed some service requests services (#357)

* drop immunization dose_status, dose_status_reason (#358)

* permitted_episodes are now not required in cancel/recall service request WS (#352)

* medical events scheduler app and config fixed (#355)

* service request autoexpiration datetime fixed (#354)

* don't close service request on episode close (#353)

* transaction fail case (#344)

* search conditions on package create (#335)

* fail on transaction service failure (#334)

* use only active approvals for abac rpc (#328)

* mix lock updated (#327)

* approvals_resend_sms job response fixed (#325)

* validate service request expiration error code changed to 422 (create approval) (#323)

* Resend SMS on approval fix (#320)

* service request validations (#306)

* create approval validation fixed (#300)

* approval response data in job details response added (#298)

* use, create service requests (#291)

* bump alpine (#287)

* fix service request schemas (#285)

* status check for devices in cancel package ws (#284)

* approval otp verification response fixed, job creation hash func changed (#283)

* replace mpi rpc module (#280)

* job response length calculations (#277)

* create approval fixed (#273)

* Updated recall and cancel service request schemas (#274)

* employee validator fix (#272)

* use service request fixes (#270)

* remote patient_id from use, release service request (#267)

* fail on saving to media storage (#264)
