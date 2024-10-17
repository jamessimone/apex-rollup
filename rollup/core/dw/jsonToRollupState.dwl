%dw 2.0
input records application/json
output application/apex

var getCompliantSObject = (item) -> item filterObject (value, key) -> (("" ++ key) != "attributes")
---
// String coercion used to avoid errors like:
// Invalid type: "org.mule.weave.v2.model.values.MaterializedAttributeDelegateValue"
records map (record) -> "" ++ record.typeName match {
    case "RollupState.GenericInfo" -> record as Object { class: $ }
    case "RollupState.AverageInfo" -> record as Object { class: $ }
    case "RollupState.SObjectInfo" -> {
            commitCount: record.commitCount,
            key: record.key,
            keyLength: record.keyLength,
            item: getCompliantSObject(record.item) as Object { class: "" ++ record.itemType },
            recordId: record.recordId,
        } as Object { class: $ }
    case "RollupState.MostInfo" -> record as Object { class: $ }
}