public without sharing virtual class RollupState implements System.Queueable, System.Finalizer {
  protected transient String key;
  protected transient Integer keyLength;
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

  public virtual override String toString() {
    throw new SerializationException('Should not make it here');
  }

  public class AverageInfo extends RollupState {
    public Decimal denominator = 0;
    public Decimal numerator = 0;
    public Set<Object> distinctNumerators {
      get {
        this.distinctNumerators = this.distinctNumerators ?? new Set<Object>();
        return this.distinctNumerators;
      }
      private set;
    }

    public void increment(Decimal value) {
      this.numerator += value;
      this.denominator++;
      this.distinctNumerators.add(value);
    }

    public override Type getType() {
      return AverageInfo.class;
    }

    public override String toString() {
      return JSON.serialize(
        new Map<String, Object>{
          'denominator' => this.denominator,
          'distinctNumerators' => this.distinctNumerators,
          'key' => this.key,
          'keyLength' => this.keyLength,
          'numerator' => this.numerator,
          'type' => this.getType().getName()
        }
      );
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

    public override String toString() {
      return JSON.serialize(
        new Map<String, Object>{
          'largestPointCounter' => this.largestPointCounter,
          'key' => this.key,
          'keyLength' => this.keyLength,
          'type' => this.getType().getName(),
          'value' => this.value
        }
      );
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

    public override String toString() {
      return JSON.serialize(
        new Map<String, Object>{ 'item' => this.item, 'key' => this.key, 'keyLength' => this.keyLength, 'type' => this.getType().getName() }
      );
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

    public virtual override String toString() {
      return JSON.serialize(
        new Map<String, Object>{ 'key' => this.key, 'keyLength' => this.keyLength, 'type' => this.getType().getName(), 'value' => this.value }
      );
    }

    public virtual override RollupState parse(Map<String, Object> values) {
      this.value = values.get('value');
      return this;
    }
  }

  public void loadState(String jobId, Set<String> relatedRecordKeys) {
    List<RollupState__c> matchingState = this.loadOrRetrieveCachedState(jobId, relatedRecordKeys);
    List<Map<String, Object>> untypedStates = new List<Map<String, Object>>();
    for (RollupState__c state : matchingState) {
      if (state.IsCached__c == false) {
        state.IsCached__c = true;
        List<String> innerStates = new List<String>{
          state.Body0__c,
          state.Body1__c,
          state.Body2__c,
          state.Body3__c,
          state.Body4__c,
          state.Body5__c,
          state.Body6__c,
          state.Body7__c,
          state.Body8__c,
          state.Body9__c
        };
        for (String innerState : innerStates) {
          if (innerState != null) {
            // this is bad, but JSON.deserialize doesn't support List<Map<String, Object>> so there's just bad options all the way down
            List<String> splitStates = innerState.split('\\},');
            for (String splitState : splitStates) {
              untypedStates.add((Map<String, Object>) JSON.deserializeUntyped(splitState.endsWith('}') ? splitState : splitState + '}'));
            }
          }
        }
      }
    }
    for (Map<String, Object> untypedState : untypedStates) {
      RollupState parsedState = getTypedState(untypedState);
      this.keyToState.put(parsedState.key, parsedState);
    }
  }

  @SuppressWarnings('PMD.ApexCrudViolation')
  public void commitState(String jobId) {
    Map<String, List<RollupState>> relatedRecordsToStates = this.populateRelatedRecordStates();
    List<RollupState__c> stateToInsert = new List<RollupState__c>();
    List<List<String>> overflowStatesList = new List<List<String>>();
    for (String relatedRecordsKey : relatedRecordsToStates.keySet()) {
      List<RollupState> matchingStates = relatedRecordsToStates.get(relatedRecordsKey);

      List<List<String>> serializedStatesList = new List<List<String>>{ new List<String>() };
      Integer maxBodyLength = RollupState__c.Body0__c.getDescribe().getLength();
      Integer currentLength = 0;

      for (RollupState stateToAdd : matchingStates) {
        List<String> serializedStates = serializedStatesList[serializedStatesList.size() - 1];
        String serializedState = stateToAdd.toString();

        // account for the commas
        currentLength += serializedState.length() + 1;
        // There's some undocumented soft limit to the amount of data that can be stored in a long text area
        // or, at the very least, there's something about this implementation that requires the extra space
        // the bulk safe test failed with 800 as the magic number and started passing somewhere between there and 825
        // using an extra buffer just in case
        if ((currentLength + 1100) >= maxBodyLength) {
          currentLength = 0;
          serializedStates = new List<String>();
          serializedStatesList.add(serializedStates);
        }
        serializedStates.add(serializedState);
      }
      RollupState__c toInsert = new RollupState__c(RelatedJobId__c = jobId, RelatedRecordKeys__c = relatedRecordsKey);
      for (Integer index = 0; index < serializedStatesList.size(); index++) {
        String body = String.join(serializedStatesList[index], ',');
        setBody(toInsert, body, index, overflowStatesList);
      }
      stateToInsert.add(toInsert);

      for (Integer outerIndex = 0; outerIndex < overflowStatesList.size(); outerIndex++) {
        RollupState__c anotherInsert = new RollupState__c(RelatedJobId__c = jobId, RelatedRecordKeys__c = relatedRecordsKey);
        List<String> overflowStates = overflowStatesList[outerIndex];
        for (Integer index = 0; index < overflowStates.size(); index++) {
          String body = overflowStates[index];
          setBody(anotherInsert, body, index, null);
        }
        stateToInsert.add(anotherInsert);
      }
    }
    Database.insert(stateToInsert, System.AccessLevel.SYSTEM_MODE);
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
        SELECT Id, Body0__c, Body1__c, Body2__c, Body3__c, Body4__c, Body5__c, Body6__c, Body7__c, Body8__c, Body9__c, IsCached__c, RelatedRecordKeys__c
        FROM RollupState__c
        WHERE RelatedRecordKeys__c LIKE :quotedRecordKeys AND RelatedJobId__c = :jobId
      ];
      CACHED_STATES.put(cacheKey, states);
      Database.delete(states, false, System.AccessLevel.SYSTEM_MODE);
    }
    return states;
  }

  private Map<String, List<RollupState>> populateRelatedRecordStates() {
    Map<String, List<RollupState>> relatedRecordsToStates = new Map<String, List<RollupState>>();
    Set<String> relatedRecordsJoined = new Set<String>();
    Integer relatedRecordCount = 0;
    Integer counter = 0;
    List<RollupState> currentState = new List<RollupState>();
    Integer keyToStateSize = this.keyToState.size();
    for (String key : this.keyToState.keySet()) {
      RollupState state = this.keyToState.get(key);
      // Length of RollupState__c.RelatedRecordKeys__c (255) / key size: will be 14 unless people are using Apex Rollup with keys longer than 18
      // in which case it'll end up being lower
      if (relatedRecordCount == 255 / state.keyLength) {
        relatedRecordCount = 0;
        this.fillRelatedRecordStateMap(relatedRecordsToStates, getJoinedKeys(relatedRecordsJoined), new List<RollupState>(currentState));
        relatedRecordsJoined = new Set<String>();
        currentState = new List<RollupState>();
      }
      String recordKey = key.substring(0, state.keyLength);
      relatedRecordsJoined.add(recordKey);
      currentState.add(state);

      counter++;
      relatedRecordCount++;
      if (counter == keyToStateSize) {
        this.fillRelatedRecordStateMap(relatedRecordsToStates, getJoinedKeys(relatedRecordsJoined), new List<RollupState>(currentState));
      }
    }
    return relatedRecordsToStates;
  }

  private void fillRelatedRecordStateMap(Map<String, List<RollupState>> relatedRecordsToStates, String joinKey, List<RollupState> states) {
    List<RollupState> existingStates = relatedRecordsToStates.get(joinKey);
    if (existingStates == null) {
      existingStates = new List<RollupState>();
      relatedRecordsToStates.put(joinKey, existingStates);
    }
    existingStates.addAll(states);
  }

  private static void setBody(RollupState__c state, String body, Integer index, List<List<String>> overflowStates) {
    switch on index {
      when 0 {
        state.Body0__c = body;
      }
      when 1 {
        state.Body1__c = body;
      }
      when 2 {
        state.Body2__c = body;
      }
      when 3 {
        state.Body3__c = body;
      }
      when 4 {
        state.Body4__c = body;
      }
      when 5 {
        state.Body5__c = body;
      }
      when 6 {
        state.Body6__c = body;
      }
      when 7 {
        state.Body7__c = body;
      }
      when 8 {
        state.Body8__c = body;
      }
      when 9 {
        state.Body9__c = body;
      }
      when else {
        List<String> overflow;
        if (Math.mod(index, 10) == 0) {
          overflow = new List<String>();
          overflowStates.add(overflow);
        } else {
          overflow = overflowStates[overflowStates.size() - 1];
        }
        overflow.add(body);
      }
    }
  }

  private static RollupState getTypedState(Map<String, Object> untypedState) {
    RollupState parsedState = ((RollupState) Type.forName((String) untypedState.get('type')).newInstance()).parse(untypedState);
    parsedState.key = (String) untypedState.get('key');
    parsedState.keyLength = (Integer) untypedState.get('keyLength');
    return parsedState;
  }

  private static String getJoinedKeys(Iterable<String> values) {
    return String.join(values, ',');
  }

  private static String getMetadataKey(Rollup__mdt meta) {
    return meta.CalcItem__c +
      meta.RollupFieldOnCalcItem__c +
      meta.LookupFieldOnCalcItem__c +
      meta.RollupOperation__c +
      meta.LookupObject__c +
      meta.RollupFieldOnLookupObject__c +
      meta.LookupFieldOnLookupObject__c;
  }
}
