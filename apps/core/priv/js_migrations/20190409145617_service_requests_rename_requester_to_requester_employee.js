db.getCollection('service_requests').updateMany({}, {$rename: {"requester": "requester_employee"}})
