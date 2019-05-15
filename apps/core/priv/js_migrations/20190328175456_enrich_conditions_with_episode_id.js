db.conditions.find({ context_episode_id: { $exists: false } }).forEach(function (condition) {
  var patient = db.patients.findOne({ _id: condition.patient_id });
  for (var key in patient.encounters) {
    if (UUID(key).hex() == condition.context.identifier.value.hex()) {
      db.conditions.updateOne(
        { _id: condition._id },
        {
          $set: { context_episode_id: patient.encounters[key].episode.identifier.value }
        });
      return;
    }
  }
});
