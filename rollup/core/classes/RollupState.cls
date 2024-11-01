public without sharing virtual class RollupState implements System.Queueable, System.Finalizer, RollupLogger.ToStringObject {
  protected transient String key;
  protected transient Integer keyLength;
  protected transient String recordId;
  protected transient String typeName;
  protected final Set<String> jobIds = new Set<String>();

  private Long commitCount = 1;
  private Set<Id> statefulPreviouslyRetrievedStateIds = new Set<Id>();

  @TestVisible
  private static Integer maxBodyLength = 131072;
  @TestVisible
  private static Integer maxRelatedKeysLength = 255;

  private static final Map<String, RollupState> KEY_TO_STATE {
    get {
      KEY_TO_STATE = KEY_TO_STATE ?? new Map<String, RollupState>();
      return KEY_TO_STATE;
    }
    set;
  }

  private static final Map<String, List<RollupState__c>> CACHED_STATES {
    get {
      CACHED_STATES = CACHED_STATES ?? new Map<String, List<RollupState__c>>();
      return CACHED_STATES;
    }
    set;
  }

  public RollupState getState(String key, Rollup__mdt meta, Type initializingType) {
    String trueKey = (key + getMetadataKey(meta));
    RollupState possibleState = KEY_TO_STATE.get(trueKey);
    if (possibleState == null) {
      possibleState = (RollupState) initializingType.newInstance();
      possibleState.recordId = key;
      // we only pass the original key's length because even though state is keyed by the trueKey
      // the original key's length gives us access to the record key when committing state values to the
      // various RelatedRecordKey{n}__c fields
      this.setState(trueKey, key.length(), possibleState);
    }
    return possibleState;
  }

  public void setState(String key, Integer keyLength, RollupState state) {
    state.commitCount = this.commitCount;
    state.key = key;
    state.keyLength = keyLength;
    KEY_TO_STATE.put(state.key, state);
  }

  public override String toString() {
    return '' + this.getUntypedState();
  }

  public virtual Map<String, Object> getUntypedState() {
    throw new SerializationException('Should not make it here');
  }

  public virtual Boolean isEmpty() {
    throw new IllegalArgumentException('Should not make it here');
  }

  public class AverageInfo extends RollupState {
    public Decimal denominator = 0;
    public Decimal numerator = 0;
    public Set<Object> distinctNumerators = new Set<Object>();

    public void increment(Decimal value) {
      this.numerator += value;
      this.denominator++;
      this.distinctNumerators.add(value);
    }

    public override Boolean isEmpty() {
      return this.denominator == 0;
    }

    public override Map<String, Object> getUntypedState() {
      return new Map<String, Object>{
        'denominator' => this.denominator,
        'distinctNumerators' => this.distinctNumerators,
        'key' => this.key,
        'keyLength' => this.keyLength,
        'numerator' => this.numerator,
        'typeName' => AverageInfo.class.getName()
      };
    }
  }

  public class MostInfo extends GenericInfo {
    public Integer largestPointCounter = -1;

    public void setValues(Integer newWinner, Object val) {
      this.largestPointCounter = newWinner;
      this.value = val;
    }

    public override Boolean isEmpty() {
      return this.largestPointCounter == -1;
    }

    public override Map<String, Object> getUntypedState() {
      return new Map<String, Object>{
        'largestPointCounter' => this.largestPointCounter,
        'key' => this.key,
        'keyLength' => this.keyLength,
        'typeName' => MostInfo.class.getName(),
        'value' => this.value
      };
    }
  }

  public class SObjectInfo extends RollupState {
    public SObject item;

    public void setItem(SObject item) {
      this.item = item;
    }

    public override Boolean isEmpty() {
      return this.item == null;
    }

    public override Map<String, Object> getUntypedState() {
      return new Map<String, Object>{
        'item' => this.item,
        'itemType' => '' + this.item.getSObjectType(),
        'key' => this.key,
        'keyLength' => this.keyLength,
        'typeName' => SObjectInfo.class.getName()
      };
    }
  }

  /**
   * In theory, GenericInfo is overkill for what it does - any rollup operation that can be reduced to a single value
   * COULD simply take whatever the current value on the parent record is as the source of truth. That being said, the
   * prior implementation with `Database.Stateful` shamefully split the logic between `RollupAsyncProcessor` and `RollupState`
   * when managing prior values, and duplicating _some_ data here (as far as what eventually gets persisted to the database as `RollupState__c` records)
   * seems vastly preferable as opposed to the logic living in two different places
   */
  public virtual class GenericInfo extends RollupState {
    public Object value;

    public void setValue(Object newValue) {
      this.value = newValue;
    }

    public virtual override Boolean isEmpty() {
      return this.value == null;
    }

    public virtual override Map<String, Object> getUntypedState() {
      return new Map<String, Object>{ 'key' => this.key, 'keyLength' => this.keyLength, 'typeName' => GenericInfo.class.getName(), 'value' => this.value };
    }
  }

  public void loadState(String jobId, Set<String> relatedRecordKeys) {
    this.jobIds.add(jobId);
    List<RollupState__c> matchingState = this.loadOrRetrieveCachedState(jobId, relatedRecordKeys);
    for (RollupState__c state : matchingState) {
      if (this.statefulPreviouslyRetrievedStateIds.contains(state.Id) == false && state.Body0__c != null) {
        List<Object> localUncastStates = (List<Object>) new DataWeaveScriptResource.jsonToRollupState()
          .execute(new Map<String, Object>{ 'records' => '[' + state.Body0__c + ']' })
          .getValue();
        for (Object uncastState : localUncastStates) {
          RollupState castState = (RollupState) uncastState;
          KEY_TO_STATE.put(castState.key, castState);
        }
      }
      this.statefulPreviouslyRetrievedStateIds.add(state.Id);
    }
  }

  public void commitState(String jobId) {
    this.jobIds.add(jobId);
    this.populateRelatedRecordStates(jobId);
  }

  public String cleanup(Set<String> jobIds) {
    this.jobIds.addAll(jobIds);
    RollupLogger.Instance.log('about to clean up rollup state', this.jobIds, System.LoggingLevel.INFO);
    return System.enqueueJob(this);
  }

  @SuppressWarnings('PMD.ApexCrudViolation')
  public void execute(System.QueueableContext qc) {
    System.attachFinalizer(this);
    List<RollupState__c> matchingState = [
      SELECT Id
      FROM RollupState__c
      WHERE RelatedJobId__c = :this.jobIds
      LIMIT :Limits.getLimitDmlRows() - Limits.getDmlRows()
    ];
    Database.delete(matchingState, false, System.AccessLevel.SYSTEM_MODE);
  }

  public void execute(System.FinalizerContext fc) {
    if ([SELECT COUNT() FROM RollupState__c WHERE Id = :this.jobIds LIMIT 1] > 0) {
      new RollupState().cleanup(this.jobIds);
    }
  }

  @SuppressWarnings('PMD.ApexCrudViolation')
  private List<RollupState__c> loadOrRetrieveCachedState(String jobId, Set<String> relatedRecordKeys) {
    String cacheKey = String.join(relatedRecordKeys, '');
    List<RollupState__c> states = CACHED_STATES.get(cacheKey);
    if (relatedRecordKeys.isEmpty() || states != null) {
      RollupLogger.Instance.log('Returning state from cache for record size: ' + (states?.size() ?? 0), System.LoggingLevel.DEBUG);
      return new List<RollupState__c>();
    }
    List<String> quotedRecordKeys = new List<String>();
    for (String recordKey : relatedRecordKeys) {
      quotedRecordKeys.add('%' + recordKey + '%');
    }
    states = [
      SELECT Id, Body0__c
      FROM RollupState__c
      WHERE
        (RelatedRecordKeys0__c LIKE :quotedRecordKeys
        OR RelatedRecordKeys1__c LIKE :quotedRecordKeys
        OR RelatedRecordKeys2__c LIKE :quotedRecordKeys
        OR RelatedRecordKeys3__c LIKE :quotedRecordKeys
        OR RelatedRecordKeys4__c LIKE :quotedRecordKeys
        OR RelatedRecordKeys5__c LIKE :quotedRecordKeys
        OR RelatedRecordKeys6__c LIKE :quotedRecordKeys
        OR RelatedRecordKeys7__c LIKE :quotedRecordKeys
        OR RelatedRecordKeys8__c LIKE :quotedRecordKeys
        OR RelatedRecordKeys9__c LIKE :quotedRecordKeys
        OR RelatedRecordKeys10__c LIKE :quotedRecordKeys)
        AND RelatedJobId__c = :jobId
        AND IsDeleted = FALSE
        AND Id != :this.statefulPreviouslyRetrievedStateIds
      ORDER BY CreatedDate DESC
    ];
    CACHED_STATES.put(cacheKey, states);
    Database.delete(states, false, System.AccessLevel.SYSTEM_MODE);
    return states;
  }

  @SuppressWarnings('PMD.ApexCrudViolation, PMD.AvoidDeeplyNestedIfStmts')
  private void populateRelatedRecordStates(String jobId) {
    RollupState__c currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId);
    List<RollupState__c> statesToInsert = new List<RollupState__c>{ currentStateToInsert };
    Integer numberOfStates = KEY_TO_STATE.size();

    // mutable tracking fields
    Set<String> allRecordKeys = new Set<String>();
    Integer relatedRecordKeyLength = 0;
    Integer currentRelatedRecordFieldIndex = 0;
    Double currentLength = 0;
    Integer stateCounter = 0;
    List<Map<String, Object>> untypedStates = new List<Map<String, Object>>();
    Schema.SObjectField relatedKeysFieldToken = RollupState__c.RelatedRecordKeys0__c;
    for (String key : KEY_TO_STATE.keySet()) {
      RollupState state = KEY_TO_STATE.get(key);
      stateCounter++;
      if (state.isEmpty()) {
        continue;
      }

      String recordKey = key.substring(0, state.keyLength);
      String currentRelatedKeys = (String) currentStateToInsert.get(relatedKeysFieldToken);

      if (allRecordKeys.contains(recordKey) == false) {
        allRecordKeys.add(recordKey);
        String newKeys = currentRelatedKeys != null ? currentRelatedKeys + ',' + recordKey : recordKey;
        currentStateToInsert.put(relatedKeysFieldToken, newKeys);
        relatedRecordKeyLength = newKeys.length();
      }
      Map<String, Object> untypedState = state.getUntypedState();
      // 1.1 is enough of a buffer for the serialized version with quoted characters and the + 1 accounts for commas as the delimiter between state objects
      currentLength += (untypedState.toString().length() * 1.1) + 1;
      untypedStates.add(untypedState);

      // if the next key would overflow the current related keys field, either step to the new field
      // or add a new state record to the list if we're out of key fields
      if (relatedRecordKeyLength + state.keyLength + 1 > maxRelatedKeysLength) {
        currentRelatedRecordFieldIndex++;
        TokenSentinel sentinel = getRelatedRecordKeySentinel(currentRelatedRecordFieldIndex);
        Boolean isMissingCurrentKey = allRecordKeys.contains(recordKey) == false;
        if (relatedKeysFieldToken == RollupState__c.RelatedRecordKeys10__c) {
          if (isMissingCurrentKey) {
            untypedStates.remove(untypedStates.size() - 1);
          }
          allRecordKeys = new Set<String>();
          currentStateToInsert.Body0__c = getJoinedBody(untypedStates);
          relatedKeysFieldToken = RollupState__c.RelatedRecordKeys0__c;
          currentRelatedRecordFieldIndex = 0;
          currentLength = 0;
          currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId);
          statesToInsert.add(currentStateToInsert);
          if (isMissingCurrentKey) {
            untypedStates.add(untypedState);
            currentStateToInsert.RelatedRecordKeys0__c = recordKey;
            allRecordKeys.add(recordKey);
            relatedRecordKeyLength = state.keyLength;
          }
        } else {
          relatedKeysFieldToken = sentinel.token;
          relatedRecordKeyLength = 0;
        }
      }
      // There's some undocumented soft limit to the amount of data that can be stored in a long text area
      // so we use another slight buffer to avoid running into the actual limit
      else if ((currentLength + 1100) >= maxBodyLength) {
        allRecordKeys = new Set<String>();
        currentStateToInsert.Body0__c = getJoinedBody(untypedStates);
        currentRelatedRecordFieldIndex = 0;
        relatedRecordKeyLength = 0;
        relatedKeysFieldToken = RollupState__c.RelatedRecordKeys0__c;
        currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId);
        statesToInsert.add(currentStateToInsert);
        currentLength = 0;
      }
    }
    if (stateCounter == numberOfStates && untypedStates.isEmpty() == false) {
      currentStateToInsert.Body0__c = getJoinedBody(untypedStates);
    }

    for (Integer reverseIndex = statesToInsert.size() - 1; reverseIndex >= 0; reverseIndex--) {
      RollupState__c state = statesToInsert[reverseIndex];
      if (state.Body0__c == null) {
        statesToInsert.remove(reverseIndex);
      }
    }

    Database.insert(statesToInsert, System.AccessLevel.SYSTEM_MODE);
    RollupLogger.Instance.log(
      'Finished inserting ' + statesToInsert.size() + ' states (for batch number: ' + this.commitCount + ')',
      System.LoggingLevel.DEBUG
    );
    KEY_TO_STATE.clear();
    CACHED_STATES.clear();
    this.commitCount++;
  }

  private class TokenSentinel implements RollupLogger.ToStringObject {
    public Boolean shouldReset = false;
    public Schema.SObjectField token;
    public Integer currentTokenIndex;

    public TokenSentinel(Integer currentTokenIndex) {
      this.currentTokenIndex = currentTokenIndex;
    }
  }

  private static TokenSentinel getRelatedRecordKeySentinel(Integer currentIndex) {
    TokenSentinel sentinel = new TokenSentinel(currentIndex);

    switch on currentIndex {
      when 0 {
        sentinel.token = RollupState__c.RelatedRecordKeys0__c;
      }
      when 1 {
        sentinel.token = RollupState__c.RelatedRecordKeys1__c;
      }
      when 2 {
        sentinel.token = RollupState__c.RelatedRecordKeys2__c;
      }
      when 3 {
        sentinel.token = RollupState__c.RelatedRecordKeys3__c;
      }
      when 4 {
        sentinel.token = RollupState__c.RelatedRecordKeys4__c;
      }
      when 5 {
        sentinel.token = RollupState__c.RelatedRecordKeys5__c;
      }
      when 6 {
        sentinel.token = RollupState__c.RelatedRecordKeys6__c;
      }
      when 7 {
        sentinel.token = RollupState__c.RelatedRecordKeys7__c;
      }
      when 8 {
        sentinel.token = RollupState__c.RelatedRecordKeys8__c;
      }
      when 9 {
        sentinel.token = RollupState__c.RelatedRecordKeys9__c;
      }
      when 10 {
        sentinel.token = RollupState__c.RelatedRecordKeys10__c;
      }
      when else {
        sentinel.token = RollupState__c.RelatedRecordKeys0__c;
        sentinel.shouldReset = true;
      }
    }
    return sentinel;
  }

  private static String getJoinedBody(List<Map<String, Object>> untypedStates) {
    String joinedBody = JSON.serialize(untypedStates).removeStart('[').removeEnd(']');
    untypedStates.clear();
    return joinedBody;
  }

  private static String getMetadataKey(Rollup__mdt meta) {
    return meta.DeveloperName ?? (meta.RollupOperation__c + meta.LookupObject__c + meta.RollupFieldOnLookupObject__c + meta.LookupFieldOnLookupObject__c);
  }
}
