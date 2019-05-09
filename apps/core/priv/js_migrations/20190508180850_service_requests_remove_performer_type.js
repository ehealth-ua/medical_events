db.getCollection('service_requests').updateMany({}, {$unset: {"performer_type": ""}})
