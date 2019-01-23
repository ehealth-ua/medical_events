db.getCollection('patients').updateMany({risk_assessments: {$exists: false}},{$set: {risk_assessments: {}}});
