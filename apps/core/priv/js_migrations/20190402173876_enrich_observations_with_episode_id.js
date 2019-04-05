db.observations.aggregate(
  {
    $lookup:
    {
      from: "patients",
      let: { "entity_id": "$context.identifier.value" },
      pipeline: [
        { $project: { encounters: { $objectToArray: "$encounters" } } },
        { $unwind: "$encounters" },
        { $project: { encounters: "$encounters.v" } },
        { $replaceRoot: { newRoot: "$encounters" } },
        { $match: { $expr: { $eq: ["$id", "$$entity_id"] } } }
      ],
      as: "encounters"
    }
  },
  { $unwind: "$encounters" },
  { $project: { _id: 0, observation_id: "$_id", episode_id: "$encounters.episode.identifier.value" } }
).forEach(function (thisDoc) {
  db.observations.updateOne({ _id: thisDoc.observation_id }, { $set: { context_episode_id: thisDoc.episode_id } })
});