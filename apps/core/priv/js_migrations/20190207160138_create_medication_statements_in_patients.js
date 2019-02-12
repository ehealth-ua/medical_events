db.getCollection('patients').updateMany({medication_statements: {$exists: false}},{$set: {medication_statements: {}}});
