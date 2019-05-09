db.getCollection('service_requests').update({}, {$unset: {"performer_type": ""}})
