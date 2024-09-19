public without sharing virtual class RollupState implements System.Queueable, System.Finalizer {
  protected transient String key;
  protected transient Integer keyLength;
  protected transient String typeName;
  protected final Set<String> jobIds = new Set<String>();

  private final transient Map<String, RollupState> keyToState {
    get {
      this.keyToState = this.keyToState ?? new Map<String, RollupState>();
      return this.keyToState;
    }
    set;
  }

  private static final transient Map<String, List<RollupState__c>> CACHED_STATES {
    get {
      CACHED_STATES = CACHED_STATES ?? new Map<String, List<RollupState__c>>();
      return CACHED_STATES;
    }
    set;
  }

  public RollupState getState(String key, Rollup__mdt meta) {
    return this.keyToState.get(key + getMetadataKey(meta));
  }

  public void setState(String key, Rollup__mdt meta, RollupState state) {
    state.key = key + getMetadataKey(meta);
    state.keyLength = key.length();
    this.keyToState.put(state.key, state);
  }

  public virtual Map<String, Object> getUntypedState() {
    throw new SerializationException('Should not make it here');
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

    public override Type getType() {
      return AverageInfo.class;
    }

    public override Map<String, Object> getUntypedState() {
      return new Map<String, Object>{
        'denominator' => this.denominator,
        'distinctNumerators' => this.distinctNumerators,
        'key' => this.key,
        'keyLength' => this.keyLength,
        'numerator' => this.numerator,
        'typeName' => this.getType().getName()
      };
    }

    public override RollupState parse(Map<String, Object> values) {
      this.denominator = (Decimal) values.get('denominator');
      this.numerator = (Decimal) values.get('numerator');
      this.distinctNumerators.addAll((List<Object>) values.get('distinctNumerators'));
      return this;
    }
  }

  public class MostInfo extends GenericInfo {
    public Integer largestPointCounter = -1;

    public void setValues(Integer newWinner, Object val) {
      this.largestPointCounter = newWinner;
      this.value = val;
    }

    public override Type getType() {
      return MostInfo.class;
    }

    public override Map<String, Object> getUntypedState() {
      return new Map<String, Object>{
        'largestPointCounter' => this.largestPointCounter,
        'key' => this.key,
        'keyLength' => this.keyLength,
        'typeName' => this.getType().getName(),
        'value' => this.value
      };
    }

    public override RollupState parse(Map<String, Object> values) {
      super.parse(values);
      this.largestPointCounter = (Integer) values.get('largestPointCounter');
      return this;
    }
  }

  public class SObjectInfo extends RollupState {
    public SObject item;

    public void setItem(SObject item) {
      this.item = item;
    }

    public override Type getType() {
      return SObjectInfo.class;
    }

    public override Map<String, Object> getUntypedState() {
      return new Map<String, Object>{
        'item' => this.item,
        'key' => this.key,
        'keyLength' => this.keyLength,
        'typeName' => this.getType().getName(),
        'itemType' => '' + this.item.getSObjectType()
      };
    }

    public override RollupState parse(Map<String, Object> values) {
      this.item = (SObject) values.get('item');
      return this;
    }
  }

  public virtual class GenericInfo extends RollupState {
    public Object value;

    public void setValue(Object newValue) {
      this.value = newValue;
    }

    public virtual override Type getType() {
      return GenericInfo.class;
    }

    public virtual override Map<String, Object> getUntypedState() {
      return new Map<String, Object>{ 'key' => this.key, 'keyLength' => this.keyLength, 'typeName' => this.getType().getName(), 'value' => this.value };
    }

    public virtual override RollupState parse(Map<String, Object> values) {
      this.value = values.get('value');
      return this;
    }
  }

  public void loadState(String jobId, Set<String> relatedRecordKeys) {
    List<RollupState__c> matchingState = this.loadOrRetrieveCachedState(jobId, relatedRecordKeys);
    String json = '[';
    for (RollupState__c state : matchingState) {
      if (state.IsCached__c == false) {
        state.IsCached__c = true;
        if (json != '[') {
          json += ',';
        }
        if (state.Body0__c != null) {
          json += state.Body0__c;
        }
        if (state.Body1__c != null) {
          json += ',' + state.Body1__c;
        }
        if (state.Body2__c != null) {
          json += ',' + state.Body2__c;
        }
        if (state.Body3__c != null) {
          json += ',' + state.Body3__c;
        }
        if (state.Body4__c != null) {
          json += ',' + state.Body4__c;
        }
        if (state.Body5__c != null) {
          json += ',' + state.Body5__c;
        }
        if (state.Body6__c != null) {
          json += ',' + state.Body6__c;
        }
        if (state.Body7__c != null) {
          json += ',' + state.Body7__c;
        }
        if (state.Body8__c != null) {
          json += ',' + state.Body8__c;
        }
        if (state.Body9__c != null) {
          json += ',' + state.Body9__c;
        }
      }
    }
    List<Object> uncastStates = new List<Object>();
    if (json != '[') {
      uncastStates.addAll(
        (List<Object>) new DataWeaveScriptResource.jsonToRollupState().execute(new Map<String, Object>{ 'records' => json + ']' }).getValue()
      );
      // for (Object uncastStateList : uncastStates) {
      //   List<Object> uncastStates = (List<Object>) uncastStateList;
      for (Object uncastState : uncastStates) {
        RollupState castState = (RollupState) uncastState;
        this.keyToState.put(castState.key, castState);
      }
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
    Database.delete(matchingState, System.AccessLevel.SYSTEM_MODE);
  }

  public void execute(System.FinalizerContext fc) {
    if ([SELECT COUNT() FROM RollupState__c WHERE Id = :this.jobIds LIMIT 1] > 0) {
      new RollupState().cleanup(new Set<String>(this.jobIds));
    }
  }

  protected virtual Type getType() {
    return RollupState.class;
  }

  protected virtual RollupState parse(Map<String, Object> values) {
    throw new TypeException('Not implemented');
  }

  @SuppressWarnings('PMD.ApexCrudViolation')
  private List<RollupState__c> loadOrRetrieveCachedState(String jobId, Set<String> relatedRecordKeys) {
    if (relatedRecordKeys.isEmpty()) {
      return new List<RollupState__c>();
    }
    String cacheKey = String.join(relatedRecordKeys, '');
    List<RollupState__c> states = CACHED_STATES.get(cacheKey);
    if (states == null) {
      List<String> quotedRecordKeys = new List<String>();
      for (String recordKey : relatedRecordKeys) {
        quotedRecordKeys.add('%' + recordKey + '%');
      }
      states = [
        SELECT Id, Body0__c, Body1__c, Body2__c, Body3__c, Body4__c, Body5__c, Body6__c, Body7__c, Body8__c, Body9__c, IsCached__c
        FROM RollupState__c
        WHERE RelatedRecordKeysIndex__c LIKE :quotedRecordKeys AND RelatedJobId__c = :jobId
      ];
      CACHED_STATES.put(cacheKey, states);
      Database.delete(states, false, System.AccessLevel.SYSTEM_MODE);
    }
    return states;
  }

  @SuppressWarnings('PMD.ApexCrudViolation')
  private void populateRelatedRecordStates(String jobId) {
    RollupState__c currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId);
    List<RollupState__c> statesToInsert = new List<RollupState__c>{ currentStateToInsert };
    Set<String> relatedRecordKeys = new Set<String>();
    Integer relatedRecordKeyLength = 0;
    Integer currentRelatedRecordFieldIndex = 0;
    Integer currentBodyFieldIndex = 0;
    // all of the Body fields share the same length
    Integer maxBodyLength = RollupState__c.Body0__c.getDescribe().getLength();
    Integer currentLength = 0;
    List<Map<String, Object>> untypedStates = new List<Map<String, Object>>();
    Schema.SObjectField relatedKeysFieldToken = RollupState__c.RelatedRecordKeys__c;
    Schema.SObjectField relatedBodyFieldToken = RollupState__c.Body0__c;
    Boolean hasSetBody = false;
    Boolean hasSetRelatedRecords = false;
    for (String key : this.keyToState.keySet()) {
      RollupState state = this.keyToState.get(key);

      if (relatedRecordKeyLength + state.keyLength + 1 > 255) {
        TokenSentinel sentinel = getRelatedRecordKeySentinel(currentRelatedRecordFieldIndex);
        relatedKeysFieldToken = sentinel.token;
        hasSetRelatedRecords = true;
        relatedRecordKeyLength = 0;
        currentStateToInsert.put(sentinel.token, getJoinedKeys(relatedRecordKeys));
        relatedRecordKeys = new Set<String>();
        if (sentinel.shouldReset) {
          currentStateToInsert.put(relatedBodyFieldToken, getJoinedBody(untypedStates));
          untypedStates = new List<Map<String, Object>>();
          hasSetBody = false;
          hasSetRelatedRecords = false;
          currentRelatedRecordFieldIndex = 0;
          currentBodyFieldIndex = 0;
          currentLength = 0;
          relatedBodyFieldToken = RollupState__c.Body0__c;
          currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId);
          statesToInsert.add(currentStateToInsert);
        } else {
          currentRelatedRecordFieldIndex++;
          hasSetRelatedRecords = false;
        }
      }
      String recordKey = key.substring(0, state.keyLength);
      if (relatedRecordKeys.contains(recordKey) == false) {
        relatedRecordKeyLength += state.keyLength + 1;
        relatedRecordKeys.add(recordKey);
      }
      Map<String, Object> untypedState = state.getUntypedState();
      String serializedState = '' + untypedState;

      // 1.1 is enough of a buffer for the serialized version with quoted characters and the + 1 accounts for commas as the delimiter between objects
      currentLength += (serializedState.length() * 1.1).intValue() + 1;
      // There's some undocumented soft limit to the amount of data that can be stored in a long text area
      // so we use another slight buffer to avoid running into the actual limit
      if ((currentLength + 1100) >= maxBodyLength) {
        TokenSentinel sentinel = getBodySentinel(currentBodyFieldIndex);
        relatedBodyFieldToken = sentinel.token;
        hasSetBody = true;
        currentLength = 0;

        currentStateToInsert.put(sentinel.token, getJoinedBody(untypedStates));
        if (sentinel.shouldReset) {
          currentStateToInsert.put(relatedKeysFieldToken, getJoinedKeys(relatedRecordKeys));
          relatedRecordKeys = new Set<String>();
          hasSetBody = false;
          hasSetRelatedRecords = false;
          currentRelatedRecordFieldIndex = 0;
          currentBodyFieldIndex = 0;
          currentLength = 0;
          relatedRecordKeyLength = 0;
          relatedKeysFieldToken = RollupState__c.RelatedRecordKeys__c;
          currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId);
          statesToInsert.add(currentStateToInsert);
        } else {
          currentBodyFieldIndex++;
          hasSetBody = false;
        }
        untypedStates = new List<Map<String, Object>>();
      }
      untypedStates.add(untypedState);
    }
    if (hasSetBody == false) {
      TokenSentinel sentinel = getBodySentinel(currentBodyFieldIndex);
      if (sentinel.shouldReset) {
        currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId, RelatedRecordKeys__c = getJoinedKeys(relatedRecordKeys));
        statesToInsert.add(currentStateToInsert);
      }
      currentStateToInsert.put(relatedBodyFieldToken, getJoinedBody(untypedStates));
    }
    if (hasSetRelatedRecords == false) {
      TokenSentinel sentinel = getRelatedRecordKeySentinel(currentRelatedRecordFieldIndex);
      if (sentinel.shouldReset) {
        currentStateToInsert = new RollupState__c(RelatedJobId__c = jobId, Body0__c = getJoinedBody(untypedStates));
        statesToInsert.add(currentStateToInsert);
      }
      currentStateToInsert.put(sentinel.token, getJoinedKeys(relatedRecordKeys));
    }
    Database.insert(statesToInsert, System.AccessLevel.SYSTEM_MODE);
  }

  private class TokenSentinel {
    public Boolean shouldReset = false;
    public Schema.SObjectField token;
  }

  private static TokenSentinel getRelatedRecordKeySentinel(Integer currentIndex) {
    TokenSentinel sentinel = new TokenSentinel();

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
      when else {
        sentinel.token = RollupState__c.RelatedRecordKeys__c;
        sentinel.shouldReset = true;
      }
    }
    return sentinel;
  }

  private static TokenSentinel getBodySentinel(Integer currentIndex) {
    TokenSentinel sentinel = new TokenSentinel();

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
      when 5 {
        sentinel.token = RollupState__c.Body5__c;
      }
      when 6 {
        sentinel.token = RollupState__c.Body6__c;
      }
      when 7 {
        sentinel.token = RollupState__c.Body7__c;
      }
      when 8 {
        sentinel.token = RollupState__c.Body8__c;
      }
      when 9 {
        sentinel.token = RollupState__c.Body9__c;
      }
      when else {
        sentinel.token = RollupState__c.Body0__c;
        sentinel.shouldReset = true;
      }
    }
    return sentinel;
  }

  private static String getJoinedBody(List<Map<String, Object>> untypedStates) {
    return JSON.serialize(untypedStates).removeStart('[').removeEnd(']');
  }

  private static String getJoinedKeys(Iterable<String> values) {
    return String.join(values, ',');
  }

  private static String getMetadataKey(Rollup__mdt meta) {
    return meta.DeveloperName ?? (meta.RollupOperation__c + meta.LookupObject__c + meta.RollupFieldOnLookupObject__c + meta.LookupFieldOnLookupObject__c);
  }
}
