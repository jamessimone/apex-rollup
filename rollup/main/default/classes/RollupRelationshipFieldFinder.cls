/**
 * Big caveat here - this class can only be used with lookup relationships. The larger Rollup framework
 * accepts and even welcomes text-based keys being used, but here we accept that text-based keys
 * are likely niche, anyway, and that people looking to make use of a grandchild -> grandparent (or greater!)
 * rollup are likely operating using lookups anyway
 */
public without sharing class RollupRelationshipFieldFinder {
  private final List<String> originalParts;
  private final Traversal traversal;
  private final SObjectType ultimateParent;
  private final RollupControl__mdt rollupControl;
  private final Map<Id, SObject> oldRecords;
  private final Set<String> uniqueFinalFieldNames;

  private List<SObject> recommencementRecords;
  private List<SObject> records;
  private List<String> relationshipParts;
  private Boolean isFirstRun = true;

  public RollupRelationshipFieldFinder(RollupControl__mdt rollupControl, String relationshipPathName, Set<String> uniqueFinalFieldNames, SObjectType ultimateParent, Map<Id, SObject> oldRecords) {
    this.traversal = new Traversal(this);
    this.relationshipParts = relationshipPathName.split('\\.');
    this.rollupControl = rollupControl;
    this.ultimateParent = ultimateParent;
    this.oldRecords = oldRecords;
    this.uniqueFinalFieldNames = uniqueFinalFieldNames;

    if (this.relationshipParts.size() == 1) {
      String fieldName = this.relationshipParts[0];
      this.relationshipParts.set(0, ultimateParent.getDescribe().getName());
      this.relationshipParts.add(fieldName);
    }
    this.originalParts = new List<String>(this.relationshipParts);
  }

  public class Traversal {
    private Boolean isFinished = false;
    private Boolean isAbortedEarly = false;

    private final Map<Id, SObject> lookupIdToFinalRecords = new Map<Id, SObject>();
    private Map<Id, List<Id>> lookupIdMap = new Map<Id, List<Id>>();
    private final Map<Id, List<Id>> hierarchy = new Map<Id, List<Id>>();
    private final RollupRelationshipFieldFinder finder;

    public Traversal(RollupRelationshipFieldFinder finder) {
      this.finder = finder;
    }

    public Boolean getIsFinished() {
      return this.isFinished;
    }

    public SObject retrieveParent(Id descendantId) {
      return this.lookupIdToFinalRecords.get(descendantId);
    }

    public List<SObject> getAllParents() {
      if(this.isAbortedEarly) {
        return new List<SObject>();
      }
      // not ideal, but because multiple parents can be tied to different descendants ...
      return new List<SObject>(new Set<SObject>(this.lookupIdToFinalRecords.values()));
    }

    public void recommence() {
      this.finder.getParents(this.finder.recommencementRecords);
    }

    public Map<String, List<SObject>> getParentLookupToRecords() {
      Map<String, List<SObject>> parentToLookupRecords = new Map<String, List<SObject>>();
      if(this.isAbortedEarly) {
        return parentToLookupRecords;
      }
      for(SObject record : this.finder.records) {
        SObject parentRecord = this.retrieveParent(record.Id);
        if(parentToLookupRecords.containsKey(parentRecord.Id)) {
          parentToLookupRecords.get(parentRecord.Id).add(record);
        } else {
          parentToLookupRecords.put(parentRecord.Id, new List<SObject>{ record });
        }
      }
      return parentToLookupRecords;
    }

    public Boolean isUltimatelyReparented(SObject record, String relationshipFieldName) {
      Id currentLookupId = (Id) record.get(relationshipFieldName);
      Id oldLookupId = (Id) (this.finder.oldRecords.containsKey(record.Id)
        ? this.finder.oldRecords.get(record.Id).get(relationshipFieldName)
        : currentLookupId);
      if (currentLookupId == oldLookupId) {
        return false;
      } else if (currentLookupId == null || oldLookupId == null) {
        // this is pretty cut and dry. if we are moving from having a lookup to not having one, or vice versa, it's a reparenting
        return true;
      }
      List<Id> currentHierarchy = this.hierarchy.get(currentLookupId);
      List<Id> oldHierarchy = this.hierarchy.get(oldLookupId);
      if (currentHierarchy.size() > 0 && oldHierarchy.size() > 0) {
        // the last Ids present in the chain have to match, otherwise it's a reparenting
        return currentHierarchy[currentHierarchy.size() - 1] != oldHierarchy[oldHierarchy.size() - 1];
      } else {
        // if there was only one hop, we can just compare the Ids
        return currentLookupId != oldLookupId;
      }
    }
  }

  public Traversal getParents(List<SObject> records) {
    if (records.isEmpty() || this.relationshipParts.isEmpty()) {
      this.traversal.isFinished = true;
      return this.traversal;
    } else if (
      this.rollupControl.MaxQueryRows__c < Limits.getQueries() ||
      Limits.getLimitQueryRows() / 4 < Limits.getQueryRows() ||
      Limits.getLimitHeapSize() / 2 < Limits.getHeapSize()
    ) {
      return this.traversal;
    }

    // even before the recursion begins, the List won't be strongly typed
    SObjectType baseSObjectType = records[0].getSObjectType();
    if (baseSObjectType == this.ultimateParent) {
      this.prepFinishedObject(records);
      return this.traversal;
    } else {
      return this.recurseThroughObjectChain(records, baseSObjectType);
    }
  }

  private SObjectField getField(Map<String, SObjectField> fieldMap, String relationshipPart) {
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

  private Set<Id> getDescendantIds(Id lookupId, Set<Id> descendantIds) {
    Boolean hasMatch = this.traversal.lookupIdMap.containsKey(lookupId);
    if (hasMatch) {
      List<Id> extraIds = this.traversal.lookupIdMap.get(lookupId);
      for (Id descendantId : extraIds) {
        descendantIds.addAll(this.getDescendantIds(descendantId, descendantIds));
      }
      return descendantIds;
    }
    descendantIds.add(lookupId);
    return descendantIds;
  }

  private void prepFinishedObject(List<SObject> records) {
    this.traversal.isFinished = true;
    for (SObject record : records) {
      Set<Id> descendantIds = this.getDescendantIds(record.Id, new Set<Id>());
      for(Id descendantId : descendantIds) {
        if (descendantId != record.Id) {
          this.traversal.lookupIdToFinalRecords.put(descendantId, record);
        }
      }
    }
    this.traversal.isFinished = true;
    this.relationshipParts = this.originalParts; // reset to initial state in case outer method is re-called
    this.traversal.lookupIdMap = new Map<Id,List<Id>>(); // try to spare the heap
  }

  private Traversal recurseThroughObjectChain(List<SObject> records, SObjectType baseSObjectType) {
    // cache the latest records through in case we need to continue later
    this.recommencementRecords = records;
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

        if(this.traversal.lookupIdMap.containsKey(lookupId)) {
          this.traversal.lookupIdMap.get(lookupId).add(record.Id);
        } else {
          this.traversal.lookupIdMap.put(lookupId, new List<Id>{ record.Id });
        }

        if (this.isFirstRun) {
          // we need to keep track of potentially reparented lookups to aid with the note below
          if (this.oldRecords.containsKey(record.Id)) {
            Id oldLookupId = (Id) this.oldRecords.get(record.Id).get(field);
            if (String.isNotBlank(oldLookupId) && oldLookupId != lookupId) {
              lookupIds.add(oldLookupId);
              this.traversal.hierarchy.put(oldLookupId, new List<Id>{ oldLookupId });
            }
          }
          this.traversal.hierarchy.put(lookupId, new List<Id>{ lookupId });
        } else if (this.traversal.hierarchy.containsKey(record.Id)) {
          // track the hierarchy of objects to help in determining whether or not something
          // has ultimately been reparented
          // for example:
          // * Object 1 -> Parent 1 -> Grandparent 1 could be updated to
          // * Object 1 -> Parent 2 -> Grandparent 1
          // this would "traditionally" be a reparenting situation, but if we are skipping
          // the intermediate objects for a rollup and the end result is the same, we need
          // to avoid reporting false positives like this one
          this.traversal.hierarchy.get(record.Id).add(lookupId);
        }
      }
    }
    // no matter how far up the chain we are, if we arrive at a point where there are no records, we're done
    if(firstId == null) {
      this.prepFinishedObject(records);
      this.traversal.isAbortedEarly = true;
      return this.traversal;
    }

    String nextFieldToLookup = this.relationshipParts[0].replace('__r', '__c');
    SObjectType nextSObjectType = firstId.getSObjectType();
    SObjectField nextFieldToken = this.getField(nextSObjectType.getDescribe().fields.getMap(), nextFieldToLookup);
    List<String> fieldNames = new List<String>();
    if(nextSObjectType == this.ultimateParent) {
      fieldNames.addAll(this.uniqueFinalFieldNames);
    } else {
      fieldNames.add(nextFieldToken.getDescribe().getName());
    }
    if(fieldNames.contains('Id') == false) {
      fieldNames.add('Id');
    }
    // NB - we only support one route through polymorphic fields such as Task.WhoId and Task.WhatId for this sort of thing
    String query = 'SELECT ' + String.join(fieldNames, ',') + ' FROM ' + nextSObjectType.getDescribe().getName() + ' WHERE Id = :lookupIds';
    // recurse through till we get to the top/bottom of the chain
    if(this.isFirstRun) {
      this.records = records;
      this.isFirstRun = false;
    }
    return this.getParents(Database.query(query));
  }
}
