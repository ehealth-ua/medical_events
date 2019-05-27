defimpl String.Chars, for: BSON.ObjectId do
  def to_string(value), do: BSON.ObjectId.encode!(value)
end

defimpl String.Chars, for: BSON.Binary do
  def to_string(%BSON.Binary{binary: value, subtype: :uuid}), do: UUID.binary_to_string!(value)
end
