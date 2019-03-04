# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [1.1.0](https://github.com/edenlabllc/medical_events/compare/1.0.1...1.1.0) (2019-3-4)




### Features:

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

## [1.0.1](https://github.com/edenlabllc/medical_events/compare/1.0.1...1.0.1) (2019-1-23)



