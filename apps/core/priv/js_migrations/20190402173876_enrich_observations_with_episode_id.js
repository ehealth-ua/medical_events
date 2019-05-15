db.observations.find({ context_episode_id: { $exists: false } }).forEach(function (observation) {
  var patient = db.patients.findOne({ _id: observation.patient_id });
  for (var key in patient.encounters) {
    if (UUID(key).hex() == observation.context.identifier.value.hex()) {
      db.observations.updateOne(
        { _id: observation._id },
        {
          $set: { context_episode_id: patient.encounters[key].episode.identifier.value }
        });
      return;
    }
  }
});
