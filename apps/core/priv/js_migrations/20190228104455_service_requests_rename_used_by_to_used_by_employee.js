db.getCollection('service_requests').updateMany({}, {$rename: {"used_by": "used_by_employee"}})
