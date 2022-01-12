public without sharing virtual class RollupSObjectUpdater {
  @TestVisible
  private static final String DISPATCH_NAME = 'RollupDispatch';

  private final Schema.SObjectField fieldToken;
  private final List<IDispatcher> dispatchers;
  private final RollupPlugin plugin;

  public interface IDispatcher {
    void dispatch(List<SObject> records);
  }

  public RollupSObjectUpdater() {
    this.plugin = new RollupPlugin();
    this.dispatchers = this.fillDispatchers();
  }

  public RollupSObjectUpdater(Schema.SObjectField fieldToken) {
    this.fieldToken = fieldToken;
  }

  public virtual void doUpdate(List<SObject> recordsToUpdate) {
    // typically I wouldn't advocate for the use of a guard clause here since an empty list
    // getting updated is a no-op, but the addition of the logging item is annoying ...
    if (recordsToUpdate.isEmpty() == false) {
      RollupLogger.Instance.log('updating the following records:', recordsToUpdate, LoggingLevel.FINE);
      recordsToUpdate.sort();
      Database.DMLOptions dmlOptions = new Database.DMLOptions();
      dmlOptions.AllowFieldTruncation = true;
      Database.update(recordsToUpdate, dmlOptions);
      this.dispatch(recordsToUpdate);
    }
  }

  public void updateField(SObject record, Object value) {
    this.updateValue(record, value);
  }

  private void updateValue(SObject record, Object value) {
    Schema.DisplayType fieldType = this.fieldToken.getDescribe().getType();

    if (value instanceof Decimal) {
      Decimal decimalValue = (Decimal) value;
      if (fieldType == DisplayType.INTEGER) {
        value = decimalValue.intValue();
      }
    } else if (fieldType == DisplayType.DATE && value instanceof Datetime) {
      value = ((Datetime) value).dateGmt();
    }
    record.put(this.fieldToken, value);
  }

  private List<IDispatcher> fillDispatchers() {
    List<IDispatcher> dispatchers = new List<IDispatcher>();
    RollupPlugin__mdt dispatchPlugin = this.plugin.getInstance(DISPATCH_NAME);

    if (dispatchPlugin != null) {
      List<RollupPluginParameter__mdt> potentialRollupDispatchers = this.plugin.getMatchingParameters(dispatchPlugin.Id);
      potentialRollupDispatchers.add(new RollupPluginParameter__mdt(Value__c = DISPATCH_NAME));
      for (RollupPluginParameter__mdt pluginParameter : potentialRollupDispatchers) {
        this.fillDispatcher(dispatchers, pluginParameter.Value__c);
      }
    }

    return dispatchers;
  }

  private void dispatch(List<SObject> updatedRecords) {
    if (updatedRecords.isEmpty() == false && this.dispatchers.isEmpty() == false) {
      RollupLogger.Instance.log('dispatching updated records to: ' + this.getLogString(this.dispatchers), LoggingLevel.FINE);
      for (IDispatcher dispatcher : this.dispatchers) {
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
