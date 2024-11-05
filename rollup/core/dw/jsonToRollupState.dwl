%dw 2.0
input records application/json
output application/apex

// if the attributes property, which only exists on serialized SObjects, is present when trying to deserialize
// it leads to the following error: System.DataWeaveScriptException: Error writing item: Invalid field "attributes" for type "{your SObject Type}"
var getCompliantSObject = (item) -> item filterObject (value, key) -> (("" ++ key) != "attributes")
---
// String coercion used to avoid errors like:
// Invalid type: "org.mule.weave.v2.model.values.MaterializedAttributeDelegateValue"
records map (record) -> "" ++ record.typeName match {
                // regex here handles namespaced versions of the class name
                case matches /(.*\.|)RollupState\.SObjectInfo/ -> {
                        key: record.key,
                        keyLength: record.keyLength,
                        item: getCompliantSObject(record.item) as Object { class: "" ++ record.itemType },
                    } as Object { class: $[0] }
                else -> record as Object { class: $ }
            }