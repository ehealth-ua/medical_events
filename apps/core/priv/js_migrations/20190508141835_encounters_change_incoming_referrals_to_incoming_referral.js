db.patients.find({"encounters": {$ne: {}}}).forEach((patient) => {
  let save = false;
  Object.keys(patient.encounters).forEach((encounter_id) => {
    if (patient.encounters[encounter_id].incoming_referrals) {
      patient.encounters[encounter_id].incoming_referral = patient.encounters[encounter_id].incoming_referrals[0];
      delete patient.encounters[encounter_id].incoming_referrals;
      save = true;  
    }
    else if (!patient.encounters[encounter_id].hasOwnProperty("incoming_referral")) {
      patient.encounters[encounter_id].incoming_referral = null;
      save = true;
    }   
  });
  if (save) {
    db.patients.save(patient);
  }
});
