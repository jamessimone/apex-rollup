public without sharing virtual class RollupState implements System.Queueable, System.Finalizer, RollupLogger.ToStringObject {
  protected transient String key;
  protected transient Integer keyLength;
  protected transient String typeName;
  protected transient Long lastModified;
  protected transient Long timestamp;
  protected transient Id recordId;
  protected final Set<String> jobIds = new Set<String>();

  private Long commitCount = 1;
  private Set<Id> statefulPreviouslyRetrievedStateIds = new Set<Id>();

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
        'commitCount' => this.commitCount,
        'denominator' => this.denominator,
        'distinctNumerators' => this.distinctNumerators,
        'key' => this.key,
        'keyLength' => this.keyLength,
        'numerator' => this.numerator,
        'recordId' => this.recordId,
        'timestamp' => this.timestamp ?? System.now().getTime(),
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
        'commitCount' => this.commitCount,
        'largestPointCounter' => this.largestPointCounter,
        'key' => this.key,
        'keyLength' => this.keyLength,
        'recordId' => this.recordId,
        'timestamp' => this.timestamp ?? System.now().getTime(),
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
        'commitCount' => this.commitCount,
        'item' => this.item,
        'itemType' => '' + this.item.getSObjectType(),
        'key' => this.key,
        'keyLength' => this.keyLength,
        'recordId' => this.recordId,
        'timestamp' => this.timestamp ?? System.now().getTime(),
        'typeName' => SObjectInfo.class.getName()
      };
    }
  }

  public virtual class GenericInfo extends RollupState {
    public Object value;

    public void setValue(Object newValue) {
      this.value = newValue;
    }

    public virtual override Boolean isEmpty() {
      return this.value == null;
    }

    public virtual override Map<String, Object> getUntypedState() {
      return new Map<String, Object>{
        'commitCount' => this.commitCount,
        'key' => this.key,
        'keyLength' => this.keyLength,
        'lastModified' => System.now().getTime(),
        'recordId' => this.recordId,
        'timestamp' => this.timestamp ?? System.now().getTime(),
        'typeName' => GenericInfo.class.getName(),
        'value' => this.value
      };
    }
  }

  public void loadState(String jobId, Set<String> relatedRecordKeys) {
    Map<String, Map<Id, Datetime>> keyToDbStateInfo = new Map<String, Map<Id, Datetime>>();
    List<RollupState__c> matchingState = this.loadOrRetrieveCachedState(jobId, relatedRecordKeys);
    Map<Id, RollupState__c> idToState = new Map<Id, RollupState__c>(matchingState);
    List<Object> uncastStates = new List<Object>();
    for (RollupState__c state : matchingState) {
      if (state.IsCached__c == false) {
        state.IsCached__c = true;
        List<String> jsonParts = new List<String>();
        if (state.Body0__c != null) {
          jsonParts.add(state.Body0__c);
        }
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
            castState.recordId = state.Id;
            Map<Id, Datetime> stateIdToCreatedDate = keyToDbStateInfo.get(castState.key);
            if (stateIdToCreatedDate == null) {
              stateIdToCreatedDate = new Map<Id, Datetime>{ state.Id => state.CreatedDate };
              keyToDbStateInfo.put(castState.key, stateIdToCreatedDate);
            }
            Integer currentSize = stateIdToCreatedDate.size();
            stateIdToCreatedDate.put(state.Id, state.CreatedDate);
            if (currentSize == 1 && stateIdToCreatedDate.size() > 1) {
              System.debug('-------------------------- current commit count: ' + this.commitCount);
              System.debug('Related key shows up across multiple states: ' + stateIdToCreatedDate);
              for (Id id : stateIdToCreatedDate.keySet()) {
                System.debug('Id (' + id + ') already exists in statefulPreviouslyRetrievedStateIds? ' + this.statefulPreviouslyRetrievedStateIds.contains(id));
              }
            }
            RollupState currentStateInMap = (RollupState) KEY_TO_STATE.get(castState.key);
            if (currentStateInMap != null && currentStateInMap.timestamp != castState.timestamp) {
              System.debug('!!!!!!!!!!!!!!!!!! - would have accidentally used an out-of-date state');
              System.debug(
                'Created: ' +
                  Datetime.newInstance(currentStateInMap.timestamp) +
                  ' modified: ' +
                  Datetime.newInstance(currentStateInMap.lastModified) +
                  ' for state in map: ' +
                  currentStateInMap
              );
              System.debug(
                'Created: ' +
                  Datetime.newInstance(castState.timestamp) +
                  ' modified: ' +
                  Datetime.newInstance(currentStateInMap.lastModified) +
                  ' for state out of map: ' +
                  castState
              );
              System.debug('Cast state db record delete? ' + idToState.get(castState.recordId).IsDeleted);
              System.debug('current map state db record delete? ' + idToState.get(currentStateInMap.recordId).IsDeleted);
            } else {
              KEY_TO_STATE.put(castState.key, castState);
            }
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
      return new List<RollupState__c>();
    }
    List<String> quotedRecordKeys = new List<String>();
    for (String recordKey : relatedRecordKeys) {
      quotedRecordKeys.add('%' + recordKey + '%');
    }
    states = [
      SELECT Id, Body0__c, Body1__c, Body2__c, Body3__c, Body4__c, IsCached__c, CreatedDate, IsDeleted
      FROM RollupState__c
      WHERE
        (RelatedRecordKeys__c LIKE :quotedRecordKeys
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

  @SuppressWarnings('PMD.ApexCrudViolation')
  private void populateRelatedRecordStates(String jobId) {
    RollupState__c currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId);
    List<RollupState__c> statesToInsert = new List<RollupState__c>{ currentStateToInsert };
    // all of the Body fields share the same length
    Integer maxBodyLength = 131072;
    Integer maxRelatedKeysLength = 255;
    Integer numberOfStates = KEY_TO_STATE.size();

    // mutable tracking fields
    Set<String> relatedRecordKeys = new Set<String>();
    Set<String> allRecordKeys = new Set<String>();
    Integer relatedRecordKeyLength = 0;
    Integer currentRelatedRecordFieldIndex = 0;
    Integer currentBodyFieldIndex = 0;
    Integer currentLength = 0;
    Integer stateCounter = 0;
    List<Map<String, Object>> untypedStates = new List<Map<String, Object>>();
    Schema.SObjectField relatedKeysFieldToken = RollupState__c.RelatedRecordKeys__c;
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
      currentLength += (untypedState.toString().length() * 1.1).intValue() + 1;
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
          currentRelatedRecordFieldIndex = 0;
          currentBodyFieldIndex = 1;
          relatedRecordKeyLength = 0;
          relatedKeysFieldToken = RollupState__c.RelatedRecordKeys__c;
          currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId);
          statesToInsert.add(currentStateToInsert);
          relatedRecordKeys.add(recordKey);
        } else {
          currentBodyFieldIndex++;
        }
        currentLength = 0;
        currentStateToInsert.put(sentinel.token, getJoinedBody(untypedStates));
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
        System.debug('Removing null body');
        statesToInsert.remove(reverseIndex);
      }
    }

    Database.insert(statesToInsert, System.AccessLevel.SYSTEM_MODE);
    System.debug('Finished inserting ' + statesToInsert.size() + ' states (for batch number: ' + this.commitCount + ')');
    for (RollupState__c created : statesToInsert) {
      System.debug(created.Id);
    }
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
        sentinel.token = RollupState__c.RelatedRecordKeys__c;
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
        sentinel.token = RollupState__c.RelatedRecordKeys__c;
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
      when 1 {
        sentinel.token = RollupState__c.Body1__c;
      }
      when 2 {
        sentinel.token = RollupState__c.Body2__c;
      }
      when 3 {
        sentinel.token = RollupState__c.Body3__c;
      }
      when 4 {
        sentinel.token = RollupState__c.Body4__c;
      }
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
