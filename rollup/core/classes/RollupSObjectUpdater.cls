public without sharing virtual class RollupSObjectUpdater {
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
    switch on ex.getMessage().substringAfter('Illegal assignment from ') {
      when 'Datetime to Date' {
        record.put(this.fieldToken, ((Datetime) value).dateGmt());
      }
      when 'Decimal to Integer' {
        record.put(this.fieldToken, ((Decimal)value).intValue());
      }
      when else {
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

      RollupLogger.Instance.log('dispatching updated records to: ' + this.getLogString(dispatchers), LoggingLevel.DEBUG);
      for (IDispatcher dispatcher : dispatchers) {
        dispatcher.dispatch(updatedRecords);
      }
    }
  }

  private String getLogString(List<IDispatcher> dispatchers) {
    String baseString = '';
    String delimiter = ', ';
    for (IDispatcher dispatcher : dispatchers) {
      // NB -if toString() has been overridden on an IDispatcher, the value of that (or the value before any colon in that string)
      // will be what gets displayed, but when a class doesn't override toString(), it starts off with something like
      // "RollupSObjectUpdater:..." where the ellipsis is actually a list of member variables. without proper reflection,
      // this is as good as it gets
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
