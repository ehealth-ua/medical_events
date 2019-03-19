db.getCollection('patients').updateMany({diagnostic_reports: {$exists: false}},{$set: {diagnostic_reports: {}}});
