db.patients.find({"encounters": {$ne: {}}}).forEach((patient) => {
  Object.keys(patient.encounters).forEach((encounter_id) => {
    if (patient.encounters[encounter_id].incoming_referrals) {
      patient.encounters[encounter_id].incoming_referral = patient.encounters[encounter_id].incoming_referrals[0];
      delete patient.encounters[encounter_id].incoming_referrals;
      db.patients.save(patient);
    }
    else if (!patient.encounters[encounter_id].incoming_referral) {
      patient.encounters[encounter_id].incoming_referral = null;
      db.patients.save(patient);
    }   
  });
});
