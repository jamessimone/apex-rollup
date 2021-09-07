public virtual class RollupSObjectUpdater {
  @TestVisible
  private static RollupPluginParameter__mdt pluginParameterMock;
  private static final String DISPATCH_NAME = 'RollupDispatch';
  private final Schema.SObjectField fieldToken;

  public interface IDispatcher {
    void dispatch(List<SObject> records);
  }

  public RollupSObjectUpdater() {
  }

  public RollupSObjectUpdater(Schema.SObjectField fieldToken) {
    this.fieldToken = fieldToken;
  }

  public virtual void doUpdate(List<SObject> recordsToUpdate) {
    recordsToUpdate.sort();
    RollupLogger.Instance.log('updating the following records:', recordsToUpdate, LoggingLevel.FINE);
    Database.DMLOptions dmlOptions = new Database.DMLOptions();
    dmlOptions.AllowFieldTruncation = true;
    Database.update(recordsToUpdate, dmlOptions);
    this.dispatch(recordsToUpdate);
  }

  public void updateField(SObject record, Object value) {
    try {
      record.put(this.fieldToken, value);
    } catch (SObjectException sObjException) {
      this.handleUpdateException(sObjException, record, value);
    }
  }

  private void handleUpdateException(SObjectException ex, SObject record, Object value) {
    switch on ex.getMessage() {
      when 'Illegal assignment from Datetime to Date' {
        Datetime dtValue = (Datetime) value;
        record.put(this.fieldToken, dtValue.dateGmt());
      }
      when else {
        // so far Datetime -> Date has been the only reported issue
        // this switch statement can be expanded as necessary to deal with other problems
        throw ex;
      }
    }
  }

  private void dispatch(List<SObject> updatedRecords) {
    if (updatedRecords.isEmpty() == false) {
      RollupPlugin__mdt dispatchPlugin = RollupPlugin__mdt.getInstance(DISPATCH_NAME);
      List<RollupPluginParameter__mdt> potentialRollupDispatchers = new List<RollupPluginParameter__mdt>();
      if (dispatchPlugin != null) {
        potentialRollupDispatchers.add(new RollupPluginParameter__mdt(Value__c = DISPATCH_NAME));
        potentialRollupDispatchers.addAll(
          [SELECT Value__c FROM RollupPluginParameter__mdt WHERE RollupPlugin__c = :dispatchPlugin.Id AND DeveloperName != 'ShouldFirePlatformEvent']
        );
      }
      if (pluginParameterMock != null) {
        potentialRollupDispatchers.add(pluginParameterMock);
      }

      List<IDispatcher> dispatchers = new List<IDispatcher>();
      for (RollupPluginParameter__mdt pluginParameter : potentialRollupDispatchers) {
        this.fillDispatcher(dispatchers, pluginParameter.Value__c);
      }

      RollupLogger.Instance.log('dispatching updated records to:', this.getLogString(dispatchers), LoggingLevel.DEBUG);
      for (IDispatcher dispatcher : dispatchers) {
        dispatcher.dispatch(updatedRecords);
      }
    }
  }

  private String getLogString(List<IDispatcher> dispatchers) {
    String baseString = '';
    String delimiter = ', ';
    for (IDispatcher dispatcher : dispatchers) {
      baseString += String.valueOf(dispatcher).split(':')[0] + delimiter;
    }
    return baseString.removeEnd(delimiter);
  }

  private void fillDispatcher(List<IDispatcher> dispatchers, String typeName) {
    IDispatcher dispatcher = (IDispatcher) Type.forName(typeName)?.newInstance();
    if (dispatcher != null) {
      dispatchers.add(dispatcher);
    }
  }
}
