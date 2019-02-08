db.getCollection('medication_statements').updateMany({medication_statements: {$exists: false}},{$set: {medication_statements: {}}});
