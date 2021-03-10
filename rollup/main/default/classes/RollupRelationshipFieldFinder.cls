public without sharing class RollupRelationshipFieldFinder {

  private final List<String> relationshipParts;
  private final TraversalObject traverseObject;
  private final String rollupFieldName;
  private final String finalFieldName;

  private Boolean isFirstRun = true;

  public RollupRelationshipFieldFinder(String relationshipPathName, String rollupFieldName) {
    this.traverseObject = new TraversalObject();
    this.relationshipParts = relationshipPathName.split('\\.');
    this.rollupFieldName = rollupFieldName;
    this.finalFieldName = this.relationshipParts[this.relationshipParts.size() - 1];
  }

  public class TraversalObject {
    public Boolean isFinished = true;
    private final Map<Id, List<SObject>> lookupIdToFinalRecords = new Map<Id, List<SObject>>();
    private Map<Id, Id> lookupIdMap = new Map<Id, Id>();

    public List<SObject> retrieveParents(Id descendantId) {
      return lookupIdToFinalRecords.containsKey(descendantId) ? lookupIdToFinalRecords.get(descendantId) : new List<SObject>();
    }
  }

  // TODO: heap size, yikes
  public TraversalObject getParents(List<SObject> records) {
    if(records.isEmpty() || this.relationshipParts.isEmpty()) {
      this.traverseObject.isFinished = true;
      return this.traverseObject;
    } else if(Limits.getLimitQueries() / 2 < Limits.getQueries() || Limits.getLimitQueryRows() / 2 < Limits.getQueryRows()) {
      return this.traverseObject;
    }
    this.traverseObject.isFinished = false;

    // even before the recursion begins, the List won't be strongly typed
    SObjectType baseSObjectType = records[0].getSObjectType();
    Map<String, SObjectField> fieldMap = baseSObjectType.getDescribe().fields.getMap();
    SObjectField field = this.getField(fieldMap, this.relationshipParts.remove(0));
    
    if(field.getDescribe().getName() == this.finalFieldName) {
      this.traverseObject.isFinished = true;
      for (SObject record : records) {
        Id descendantId = this.getDescendantId(record.Id);
        if(this.traverseObject.lookupIdToFinalRecords.containsKey(descendantId)) {
          this.traverseObject.lookupIdToFinalRecords.get(descendantId).add(record);
        } else {
          this.traverseObject.lookupIdToFinalRecords.put(descendantId, new List<SObject>{ record });
        }
      }
      this.traverseObject.lookupIdMap = null; // try to spare the heap
      return this.traverseObject;
    }
    
    Set<Id> lookupIds = new Set<Id>();
    for(SObject record : records) {
      String lookupId = (String) record.get(field);
      if (String.isNotBlank(lookupId)) {
        lookupIds.add(lookupId);

        if (this.isFirstRun) {
          this.traverseObject.lookupIdMap.put(lookupId, record.Id);
        } else {
          Id ultimateDescendantId = this.getDescendantId(lookupId);
          this.traverseObject.lookupIdMap.put(lookupId, record.Id);
        }
      }
    }
    
    this.isFirstRun = false;

    String nextFieldToLookup = (this.relationshipParts.isEmpty() ? this.rollupFieldName : this.relationshipParts[0]).replace('__r', '__c');

    Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
    String query = 'SELECT Id, ' + nextFieldToLookup + ' FROM ' + fieldDescribe.getReferenceTo()[0].getDescribe().getName() + ' WHERE Id = :lookupIds';
    return this.getParents(Database.query(query));
  }

  private SObjectField getField(Map<String, SObjectField> fieldMap, String relationshipPart) {
    // this sucks, but we need to find the field with the matching relationship name
    for(String key : fieldMap.keySet()) {
      SObjectField field = fieldMap.get(key);
      if(field.getDescribe().getRelationshipName() == relationshipPart) {
        return field;
      } else if(field.getDescribe().getName() == relationshipPart) {
        return field;
      }
    }

    return null;
  }

  private Id getDescendantId(Id lookupId) {
    Boolean hasMatch = this.traverseObject.lookupIdMap.containsKey(lookupId);
    if(hasMatch) {
      return this.getDescendantId(this.traverseObject.lookupIdMap.get(lookupId));
    }
    return lookupId;
  }
    
}
