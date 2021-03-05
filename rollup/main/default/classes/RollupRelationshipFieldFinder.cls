public without sharing class RollupRelationshipFieldFinder {
  private static final Integer MAX_STACK_COUNT = 900; // 1000, but with breathing room
  private static Integer stackCount = 0;

  private Boolean isFirstRun = true;
  private SObjectType originalChildType;

  private final Set<SObjectType> processedTypes;
  private final List<SObjectType> relationshipTypes;
  private final String parentName;
  public RollupRelationshipFieldFinder(String parentName) {
    this.processedTypes = new Set<SObjectType>();
    this.relationshipTypes = new List<SObjectType>();
    this.parentName = parentName;
  }

  public List<SObjectType> getParentTypes(SObjectType childType, String childField, Id childLookup) {
    if (this.isFirstRun) {
      this.originalChildType = childType;
      this.isFirstRun = false;
    } else if (relationshipTypes.contains(originalChildType)) {
      return this.assembleFinalRelationships();
    }

    stackCount++;
    if (stackCount > MAX_STACK_COUNT) {
      return this.assembleFinalRelationships();
    }

    Map<String, SObjectField> fieldMap = childType.getDescribe().fields.getMap();
    SObjectField fieldToken = fieldMap.get(childField);
    SObjectType parentType = getSObjectType(fieldToken, childLookup.getSObjectType());

    if (fieldToken == null && childType?.getDescribe()?.getName() != 'User') {
      new RelationshipFieldResolver(this, childType).tryResolve(fieldMap, null);
    } else if (parentType?.getDescribe()?.getName() == this.parentName) {
      // new RecurseRelationshipFieldResolver(this).tryResolve(fieldMap, childType, parentType);

      this.tryAddType(parentType);
      this.tryAddType(childType);
    } else if (parentType != null) {
      Map<String, SObjectField> middleFieldMap = parentType.getDescribe().fields.getMap();
      for (String intermediateFieldName : middleFieldMap.keySet()) {
        Boolean hasInnerBreak = false;
        SObjectField middleFieldToken = middleFieldMap.get(intermediateFieldName);
        if (middleFieldToken.getDescribe().getType() != DisplayType.REFERENCE) {
          continue;
        } else {
          // recurse to try to find a way to the eventual parent
          for (SObjectType potentialParent : middleFieldToken.getDescribe().getReferenceTo()) {
            if (this.processedTypes.contains(potentialParent) == false) {
              this.processedTypes.add(potentialParent);
              // if the relationship is deeper than grandchild -> grandparent, keep going
              Id fakeIdOfType = potentialParent.getDescribe().getKeyPrefix() + '0'.repeat(12);
              String potentialName = middleFieldToken.getDescribe().getName();
              Set<SObjectType> priorSet = new Set<SObjectType>(this.relationshipTypes);
              List<SObjectType> parentTypes = getParentTypes(potentialParent, potentialName, fakeIdOfType);
              if (parentTypes.size() > priorSet.size()) {
                this.tryAddType(parentType);
                this.tryAddType(childType);
                hasInnerBreak = true;
                break;
              }
            }
          }
          if (hasInnerBreak) {
            break;
          }
        }
      }
    }
    return this.assembleFinalRelationships();
  }

  // GOOD STOPPING POINT
  private class RecurseRelationshipFieldResolver extends RelationshipFieldResolver {
    public RecurseRelationshipFieldResolver(RollupRelationshipFieldFinder finder, SObjectType type) {
      super(finder, type);
    }

    protected override void handle(SobjectField innerField) {
    }
  }

  private virtual class RelationshipFieldResolver {
    protected Boolean hasInnerBreak = false;
    protected RollupRelationshipFieldFinder finder;
    protected SObjectType type;

    public RelationshipFieldResolver(RollupRelationshipFieldFinder finder, SObjectType type) {
      this.finder = finder;
      this.type = type;
    }

    public void tryResolve(Map<String, SObjectField> fieldMap, SObjectType parentType) {
      if(this.matchesType(parentType)) {
        return;
      }
      for (String fieldName : fieldMap.keySet()) {
        SObjectField innerField = fieldMap.get(fieldName);
        if (innerField.getDescribe().getType() != DisplayType.REFERENCE) {
          continue;
        } else {
          this.handle(innerField);
        }
      }
    }

    protected virtual void handle(SObjectField innerField) {
      for (SObjectType innerType : innerField.getDescribe().getReferenceTo()) {
        if (this.matchesType(innerType)) {
          break;
        } else {
          if(innerType != null) {
            finder.processedTypes.add(innerType);
          }
          if (this.hasInnerBreak) {
            break;
          }
        }
      }
    }

    public Boolean matchesType(SObjectType innerType) {
      Boolean matches = false;
      if (innerType?.getDescribe()?.getName() == this.finder.parentName) {
        matches = true;
        this.finder.tryAddType(innerType);
        this.finder.tryAddType(this.type);
      }
      return matches;
    }
  }

  private void tryAddType(SObjectType type) {
    if (this.relationshipTypes.contains(type) == false) {
      this.relationshipTypes.add(type);
    }
  }

  private List<SObjectType> assembleFinalRelationships() {
    List<SObjectType> returnTypes = new List<SObjectType>();
    for (Integer index = this.relationshipTypes.size() - 1; index >= 0; index--) {
      returnTypes.add(this.relationshipTypes[index]);
    }
    return returnTypes;
  }

  private SObjectType getSObjectType(SObjectField fieldToken, SObjectType idType) {
    if (fieldToken == null) {
      return null;
    }
    List<SObjectType> potentialParents = fieldToken.getDescribe().getReferenceTo();
    Integer relationshipIndex = potentialParents.indexOf(idType);
    return relationshipIndex >= 0 ? potentialParents[relationshipIndex] : null;
  }
}
