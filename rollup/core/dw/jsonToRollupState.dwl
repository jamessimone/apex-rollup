%dw 2.0
import * from dw::Runtime
input records application/json
output application/apex

var getCompliantSObject = (item) -> item mapObject ((value,key) ->
    if (value matches /\d\d:\d\d:\d\d\.\d\d\dZ/) { (key): value as Time }
    else if (value matches /\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d\.\d\d\dZ/) { (key): value as DateTime }
    // I don't want to simply assume that any text that matches this pattern is a date, even though it's probably safe to do so
    // so the orElse serves as a fallback to preserve the original value
    else if (value matches /\d\d\d\d-\d\d-\d\d/ ) { (key): try(() -> value as Date) orElse value }
    else { (key) : value }
)
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
