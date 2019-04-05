db.getCollection('service_requests').updateMany({}, { $rename: { "permitted_episodes": "permitted_resources" } })
