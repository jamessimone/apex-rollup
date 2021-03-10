public without sharing class RollupRelationshipFieldFinder {
  private final List<String> relationshipParts;
  private final Traversal traverseObject;
  private final SObjectType ultimateParent;
  private final String optionalWhereClause;
  private final RollupControl__mdt rollupControl;
  private final Map<Id, SObject> oldRecords;

  private Boolean isFirstRun = true;

  public RollupRelationshipFieldFinder(RollupControl__mdt rollupControl, String relationshipPathName, SObjectType ultimateParent, Map<Id, SObject> oldRecords) {
    this.traverseObject = new Traversal(this);
    this.relationshipParts = relationshipPathName.split('\\.');
    this.rollupControl = rollupControl;
    this.ultimateParent = ultimateParent;
    this.oldRecords = oldRecords;
  }

  public RollupRelationshipFieldFinder(
    RollupControl__mdt rollupControl,
    String relationshipParts,
    SObjectType ultimateParent,
    Map<Id, SObject> oldRecords,
    String optionalWhereClause
  ) {
    this(rollupControl, relationshipParts, ultimateParent, oldRecords);
    this.optionalWhereClause = optionalWhereClause;
  }

  public class Traversal {
    public Boolean isFinished = true;
    private final Map<Id, SObject> lookupIdToFinalRecords = new Map<Id, SObject>();
    private Map<Id, Id> lookupIdMap = new Map<Id, Id>();
    private final Map<Id, List<Id>> hierarchy = new Map<Id, List<Id>>();
    private final RollupRelationshipFieldFinder finder;

    public Traversal(RollupRelationshipFieldFinder finder) {
      this.finder = finder;
    }

    public SObject retrieveParent(Id descendantId) {
      return lookupIdToFinalRecords.get(descendantId);
    }
    public Boolean isUltimatelyReparented(SObject record, String relationshipFieldName) {
      Id currentLookupId = (Id) record.get(relationshipFieldName);
      Id oldLookupId = (Id) (this.finder.oldRecords.containsKey(record.Id)
        ? this.finder.oldRecords.get(record.Id).get(relationshipFieldName)
        : currentLookupId);
      if (currentLookupId == oldLookupId) {
        return false;
      } else if (currentLookupId == null || oldLookupId == null) {
        // this is pretty cut and dry. if we are moving from having a lookup to not havine one, or vice versa, it's a reparenting
        return true;
      }
      List<Id> currentHierarchy = this.hierarchy.get(currentLookupId);
      List<Id> oldHierarchy = this.hierarchy.get(oldLookupId);
      if (currentHierarchy.size() > 0 && oldHierarchy.size() > 0) {
        return currentHierarchy[currentHierarchy.size() - 1] != oldHierarchy[oldHierarchy.size() - 1];
      } else {
        // if there was only one hop, we can just compare the Ids
        return currentLookupId != oldLookupId;
      }
    }
  }

  // TODO handle heap size
  public Traversal getParents(List<SObject> records) {
    if (records.isEmpty() || this.relationshipParts.isEmpty()) {
      this.traverseObject.isFinished = true;
      return this.traverseObject;
    } else if (this.rollupControl.MaxQueryRows__c < Limits.getQueries() || Limits.getLimitQueryRows() / 4 < Limits.getQueryRows()) {
      return this.traverseObject;
    }
    this.traverseObject.isFinished = false;

    // even before the recursion begins, the List won't be strongly typed
    SObjectType baseSObjectType = records[0].getSObjectType();
    if (baseSObjectType == this.ultimateParent) {
      this.prepFinishedObject(records);
      return this.traverseObject;
    } else {
      return this.recurseThroughObjectChain(records, baseSObjectType);
    }
  }

  private SObjectField getField(Map<String, SObjectField> fieldMap, String relationshipPart) {
    // this sucks, but we need to find the field with the matching relationship name
    for (String key : fieldMap.keySet()) {
      SObjectField field = fieldMap.get(key);
      if (field.getDescribe().getRelationshipName() == relationshipPart) {
        return field;
      } else if (field.getDescribe().getName() == relationshipPart) {
        return field;
      }
    }
    // effectively a throw; if there's no match, nothing else will work
    return null;
  }

  private Id getDescendantId(Id lookupId) {
    Boolean hasMatch = this.traverseObject.lookupIdMap.containsKey(lookupId);
    if (hasMatch) {
      return this.getDescendantId(this.traverseObject.lookupIdMap.get(lookupId));
    }
    return lookupId;
  }

  private void prepFinishedObject(List<SObject> records) {
    this.traverseObject.isFinished = true;
    for (SObject record : records) {
      Id descendantId = this.getDescendantId(record.Id);
      if (descendantId != record.Id) {
        this.traverseObject.lookupIdToFinalRecords.put(descendantId, record);
      }
    }
    this.traverseObject.lookupIdMap = null; // try to spare the heap
  }

  private Traversal recurseThroughObjectChain(List<SObject> records, SObjectType baseSObjectType) {
    String currentRelationshipName = this.relationshipParts.remove(0);
    Map<String, SObjectField> fieldMap = baseSObjectType.getDescribe().fields.getMap();
    SObjectField field = this.getField(fieldMap, currentRelationshipName);

    Set<Id> lookupIds = new Set<Id>();
    Id firstId;
    for (SObject record : records) {
      Id lookupId = (Id) record.get(field);
      if (firstId == null) {
        firstId = lookupId;
      }
      if (String.isNotBlank(lookupId)) {
        lookupIds.add(lookupId);

        this.traverseObject.lookupIdMap.put(lookupId, record.Id);
        if (this.isFirstRun) {
          // we need to keep track of potentially reparented lookups to aid with the note below
          if (this.oldRecords.containsKey(record.Id)) {
            Id oldLookupId = (Id) this.oldRecords.get(record.Id).get(field);
            if (String.isNotBlank(oldLookupId) && oldLookupId != lookupId) {
              lookupIds.add(oldLookupId);
              this.traverseObject.hierarchy.put(oldLookupId, new List<Id>{ oldLookupId });
            }
          }
          this.traverseObject.hierarchy.put(lookupId, new List<Id>{ lookupId });
        } else if (this.traverseObject.hierarchy.containsKey(record.Id)) {
          // track the hierarchy of objects to help in determining whether or not something
          // has ultimately been reparented
          // for example:
          // * Object 1 -> Parent 1 -> Grandparent 1 could be updated to
          // * Object 1 -> Parent 2 -> Grandparent 1
          // this would "traditionally" be a reparenting situation, but if we are skipping
          // the intermediate objects for a rollup and the end result is the same, we need
          // to avoid reporting false positives like this one
          this.traverseObject.hierarchy.get(record.Id).add(lookupId);
        }
      }
    }

    String nextFieldToLookup = this.relationshipParts[0].replace('__r', '__c');
    Schema.DescribeSObjectResult nextSObjectDescribe = firstId.getSObjectType().getDescribe();
    SObjectField nextFieldToken = this.getField(nextSObjectDescribe.fields.getMap(), nextFieldToLookup);
    // NB - we only support one route through polymorphic fields such as Task.WhoId and Task.WhatId for this sort of thing
    String query = 'SELECT Id, ' + nextFieldToken.getDescribe().getName() + ' FROM ' + nextSObjectDescribe.getName() + ' WHERE Id = :lookupIds';
    if (this.isFirstRun && String.isNotBlank(this.optionalWhereClause)) {
      query += '\nAND ' + this.optionalWhereClause;
    }
    // recurse through till we get to the top/bottom of the chain
    this.isFirstRun = false;
    return this.getParents(Database.query(query));
  }
}
