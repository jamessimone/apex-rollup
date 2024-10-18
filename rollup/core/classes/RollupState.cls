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
    String trueKey = (key + getMetadataKey(meta)).toLowerCase();
    RollupState possibleState = KEY_TO_STATE.get(trueKey);
    if (possibleState == null) {
      possibleState = (RollupState) initializingType.newInstance();
      possibleState.recordId = key;
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

    // TODO - experiment to see if the deserialization in Dataweave will
    // support the same map for each class such that the "value" key becomes
    // the only thing that differs between all of these "getUntypedState" declarations
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
    RollupLogger.Instance.log('Loading state for jobId: ' + jobId, System.LoggingLevel.DEBUG);
    List<RollupState__c> matchingState = this.loadOrRetrieveCachedState(jobId, relatedRecordKeys);
    for (RollupState__c state : matchingState) {
      if (state.IsCached__c == false) {
        state.IsCached__c = true;
        List<String> jsonParts = new List<String>();
        if (state.Body0__c != null) {
          jsonParts.add(state.Body0__c);
        }
        // TODO - decide if it's worth the hassle of re-implementing the correct sentinel detection necessary
        // to populate the remaining Body{n}__c fields. At the moment, for "batch" sizes of 500 children, only
        // ~12 state records were being inserted per transaction, which is an absolute pittance for the amount of data
        // each one holds, and the extra complexity of compressing the data further might be more trouble than it's worth
        if (state.Body1__c != null) {
          jsonParts.add(state.Body1__c);
        }
        if (state.Body2__c != null) {
          jsonParts.add(state.Body2__c);
        }
        if (state.Body3__c != null) {
          jsonParts.add(state.Body3__c);
        }
        if (state.Body4__c != null) {
          jsonParts.add(state.Body4__c);
        }
        for (String json : jsonParts) {
          List<Object> localUncastStates = (List<Object>) new DataWeaveScriptResource.jsonToRollupState()
            .execute(new Map<String, Object>{ 'records' => '[' + json + ']' })
            .getValue();
          for (Object uncastState : localUncastStates) {
            RollupState castState = (RollupState) uncastState;

            KEY_TO_STATE.put(castState.key, castState);
          }
        }
      }
      this.statefulPreviouslyRetrievedStateIds.add(state.Id);
    }
  }

  public void commitState(String jobId) {
    this.populateRelatedRecordStates(jobId);
  }

  public void cleanup(Set<String> jobIds) {
    this.jobIds.addAll(jobIds);
    System.enqueueJob(this);
  }

  @SuppressWarnings('PMD.ApexCrudViolation')
  public void execute(System.QueueableContext qc) {
    List<RollupState__c> matchingState = [
      SELECT Id
      FROM RollupState__c
      WHERE RelatedJobId__c = :this.jobIds
      LIMIT :(Limits.getLimitDmlRows() - (Limits.getDmlRows() + 1))
    ];
    Database.delete(matchingState, false, System.AccessLevel.SYSTEM_MODE);
  }

  public void execute(System.FinalizerContext fc) {
    if ([SELECT COUNT() FROM RollupState__c WHERE Id = :this.jobIds LIMIT 1] > 0) {
      new RollupState().cleanup(new Set<String>(this.jobIds));
    }
  }

  @SuppressWarnings('PMD.ApexCrudViolation')
  private List<RollupState__c> loadOrRetrieveCachedState(String jobId, Set<String> relatedRecordKeys) {
    String cacheKey = String.join(relatedRecordKeys, '');
    List<RollupState__c> states = CACHED_STATES.get(cacheKey);
    if (relatedRecordKeys.isEmpty() || states != null) {
      RollupLogger.Instance.log('Returning state from cache for record size: ' + states.size(), System.LoggingLevel.DEBUG);
      return new List<RollupState__c>();
    }
    List<String> quotedRecordKeys = new List<String>();
    for (String recordKey : relatedRecordKeys) {
      quotedRecordKeys.add('%' + recordKey + '%');
    }
    states = [
      SELECT
        Id,
        Body0__c,
        Body1__c,
        Body2__c,
        Body3__c,
        Body4__c,
        IsCached__c
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
    Integer maxRelatedKeysLength = 255;
    Integer numberOfStates = KEY_TO_STATE.size();

    // mutable tracking fields
    Set<String> relatedRecordKeys = new Set<String>();
    Set<String> allRecordKeys = new Set<String>();
    Integer relatedRecordKeyLength = 0;
    Integer currentRelatedRecordFieldIndex = 0;
    Integer currentBodyFieldIndex = 0;
    Double currentLength = 0;
    Integer stateCounter = 0;
    List<Map<String, Object>> untypedStates = new List<Map<String, Object>>();
    Schema.SObjectField relatedKeysFieldToken = RollupState__c.RelatedRecordKeys0__c;
    Schema.SObjectField relatedBodyFieldToken = RollupState__c.Body0__c;
    for (String key : KEY_TO_STATE.keySet()) {
      RollupState state = KEY_TO_STATE.get(key);
      stateCounter++;
      if (state.isEmpty()) {
        continue;
      }

      String recordKey = key.substring(0, state.keyLength);
      if (allRecordKeys.contains(recordKey) == false) {
        relatedRecordKeyLength += state.keyLength + 1;
        relatedRecordKeys.add(recordKey);
        allRecordKeys.add(recordKey);
      }
      Map<String, Object> untypedState = state.getUntypedState();
      // 1.1 is enough of a buffer for the serialized version with quoted characters and the + 1 accounts for commas as the delimiter between state objects
      currentLength += (untypedState.toString().length() * 1.1) + 1;
      untypedStates.add(untypedState);

      // if the next key would overflow the current related keys field, either step to the new field
      // or add a new state record to the list if we're out of key fields
      if (relatedRecordKeyLength + state.keyLength + 1 > maxRelatedKeysLength) {
        TokenSentinel sentinel = getRelatedRecordKeySentinel(currentRelatedRecordFieldIndex);
        relatedKeysFieldToken = sentinel.token;

        if (sentinel.shouldReset) {
          allRecordKeys = new Set<String>();
          if (untypedStates.isEmpty() == false) {
            currentStateToInsert.put(relatedBodyFieldToken, getJoinedBody(untypedStates));
          }
          currentRelatedRecordFieldIndex = 1;
          currentBodyFieldIndex = 0;
          currentLength = 0;
          relatedBodyFieldToken = RollupState__c.Body0__c;
          currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId);
          statesToInsert.add(currentStateToInsert);
          currentStateToInsert.put(sentinel.token, getJoinedKeys(relatedRecordKeys));
        } else {
          currentRelatedRecordFieldIndex++;
          currentStateToInsert.put(sentinel.token, getJoinedKeys(relatedRecordKeys));
        }
        relatedRecordKeyLength = 0;
      }
      // There's some undocumented soft limit to the amount of data that can be stored in a long text area
      // so we use another slight buffer to avoid running into the actual limit
      else if ((currentLength + 1100) >= maxBodyLength) {
        TokenSentinel sentinel = getBodySentinel(currentBodyFieldIndex);
        relatedBodyFieldToken = sentinel.token;

        if (sentinel.shouldReset) {
          allRecordKeys = new Set<String>();
          currentStateToInsert.put(relatedKeysFieldToken, getJoinedKeys(relatedRecordKeys));
          currentStateToInsert.put(sentinel.token, getJoinedBody(untypedStates));

          currentRelatedRecordFieldIndex = 0;
          currentBodyFieldIndex = 0;
          relatedRecordKeyLength = 0;
          relatedKeysFieldToken = RollupState__c.RelatedRecordKeys0__c;
          currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId);
          statesToInsert.add(currentStateToInsert);
          relatedRecordKeys.add(recordKey);
        } else {
          currentBodyFieldIndex++;
        }
        currentLength = 0;
      }
    }
    if (stateCounter == numberOfStates) {
      TokenSentinel bodySentinel = getBodySentinel(currentBodyFieldIndex);
      TokenSentinel relatedKeySentinel = getRelatedRecordKeySentinel(currentRelatedRecordFieldIndex);

      if ((bodySentinel.shouldReset || relatedKeySentinel.shouldReset) && untypedStates.isEmpty() == false) {
        currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId);
        statesToInsert.add(currentStateToInsert);
      }
      if (relatedRecordKeys.isEmpty() == false) {
        currentStateToInsert.put(relatedKeySentinel.token, getJoinedKeys(relatedRecordKeys));
      }
      if (untypedStates.isEmpty() == false) {
        currentStateToInsert.put(bodySentinel.token, getJoinedBody(untypedStates));
      }
    }

    for (Integer reverseIndex = statesToInsert.size() - 1; reverseIndex >= 0; reverseIndex--) {
      RollupState__c state = statesToInsert[reverseIndex];
      if (state.Body0__c == null && state.Body1__c == null && state.Body2__c == null && state.Body3__c == null && state.Body4__c == null) {
        // TODO: at the moment there's still some tracking bug with the related record keys, above, that causes currentStateToInsert to end up
        // without any corresponding body. It doesn't seem to cause any harm with the actual calculations since there's no associated data, and the keys
        // also seem to end up with the correct records without issue. While it would be nice to fix the underlying "off by one" error, this guard clause
        // suffices for the present day
        RollupLogger.Instance.log('Removing null body', System.LoggingLevel.DEBUG);
        statesToInsert.remove(reverseIndex);
      }
    }

    Database.insert(statesToInsert, System.AccessLevel.SYSTEM_MODE);
    RollupLogger.Instance.log(
      'Finished inserting ' + statesToInsert.size() + ' states (for batch number: ' + this.commitCount + ')',
      System.LoggingLevel.DEBUG
    );
    this.commitCount++;
  }

  private class TokenSentinel {
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

  private static TokenSentinel getBodySentinel(Integer currentIndex) {
    TokenSentinel sentinel = new TokenSentinel(currentIndex);

    switch on currentIndex {
      when 0 {
        sentinel.token = RollupState__c.Body0__c;
      }
      // when 1 {
      //   sentinel.token = RollupState__c.Body1__c;
      // }
      // when 2 {
      //   sentinel.token = RollupState__c.Body2__c;
      // }
      // when 3 {
      //   sentinel.token = RollupState__c.Body3__c;
      // }
      // when 4 {
      //   sentinel.token = RollupState__c.Body4__c;
      // }
      when else {
        sentinel.token = RollupState__c.Body0__c;
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

  private static String getJoinedKeys(Set<String> values) {
    String joinedKeys = String.join(values, ',');
    values.clear();
    return joinedKeys;
  }

  private static String getMetadataKey(Rollup__mdt meta) {
    return meta.DeveloperName ?? (meta.RollupOperation__c + meta.LookupObject__c + meta.RollupFieldOnLookupObject__c + meta.LookupFieldOnLookupObject__c);
  }
}
