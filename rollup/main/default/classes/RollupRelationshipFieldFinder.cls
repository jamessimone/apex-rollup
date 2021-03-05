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
    // actually counting the frames consumed is almost certainly overkill
    // but this prevents us from accidentally blowing the stack
    stackCount++;
    if (this.isFirstRun) {
      this.originalChildType = childType;
      this.isFirstRun = false;
    } else if (relationshipTypes.contains(originalChildType) || stackCount > MAX_STACK_COUNT) {
      return this.assembleFinalRelationships();
    }

    Map<String, SObjectField> fieldMap = childType.getDescribe().fields.getMap();
    SObjectField fieldToken = fieldMap.get(childField);
    SObjectType parentType = getSObjectType(fieldToken, childLookup.getSObjectType());

    /**
     * Because the sanity checks necessary to find the ultimate "one true [morty] object chain"
     * deviate slightly depending on whether or not we've reached the parent object we care about
     * (as opposed to the intermediate objects that may exist in the chain), the work is broken down
     * into two different Resolver classes that share some behavior with one another.
     */
    if (fieldToken == null && childType?.getDescribe()?.getName() != 'User') {
      // we are potentially at the top level; let's check that before moving on
      new RelationshipFieldResolver(this, childType).tryResolve(fieldMap, null);
    } else if (parentType != null) {
      // can we establish a relationship between the Id that's been passed in and the next level up in the chain?
      // let's find out - with recursion!
      Map<String, SObjectField> middleFieldMap = parentType.getDescribe().fields.getMap();
      new RecurseRelationshipFieldResolver(this, childType).tryResolve(middleFieldMap, parentType);
    }
    return this.assembleFinalRelationships();
  }

  private class RecurseRelationshipFieldResolver extends RelationshipFieldResolver {
    public RecurseRelationshipFieldResolver(RollupRelationshipFieldFinder finder, SObjectType type) {
      super(finder, type);
    }

    protected override void handle(SObjectField innerField, SObjectType parentType) {
      // recurse to try to find a way to the eventual parent
      for (SObjectType potentialParent : innerField.getDescribe().getReferenceTo()) {
        if (this.finder.processedTypes.contains(potentialParent) == false) {
          this.finder.processedTypes.add(potentialParent);
          // if the relationship is deeper than grandchild -> grandparent, keep going
          Id fakeIdOfType = potentialParent.getDescribe().getKeyPrefix() + '0'.repeat(12);
          String potentialName = innerField.getDescribe().getName();
          Set<SObjectType> priorSet = new Set<SObjectType>(this.finder.relationshipTypes);
          List<SObjectType> parentTypes = this.finder.getParentTypes(potentialParent, potentialName, fakeIdOfType);
          // I'm sure there's a better way to do this, but this is what I came up with ...
          if (parentTypes.size() > priorSet.size()) {
            this.finder.tryAddType(parentType);
            this.finder.tryAddType(this.type);
            hasInnerBreak = true;
            break;
          }
        }
      }
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
      if (this.matchesType(parentType)) {
        return;
      }
      for (String fieldName : fieldMap.keySet()) {
        SObjectField innerField = fieldMap.get(fieldName);
        if (innerField.getDescribe().getType() != DisplayType.REFERENCE) {
          continue;
        } else {
          this.handle(innerField, parentType);
        }
      }
    }

    protected virtual void handle(SObjectField innerField, SObjectType parentType) {
      for (SObjectType innerType : innerField.getDescribe().getReferenceTo()) {
        if (this.matchesType(innerType)) {
          break;
        } else {
          if (innerType != null) {
            finder.processedTypes.add(innerType);
          }
          if (this.hasInnerBreak) {
            break;
          }
        }
      }
    }

    private Boolean matchesType(SObjectType innerType) {
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
