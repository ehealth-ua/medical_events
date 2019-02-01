db.getCollection('patients').updateMany({devices: {$exists: false}},{$set: {devices: {}}});
