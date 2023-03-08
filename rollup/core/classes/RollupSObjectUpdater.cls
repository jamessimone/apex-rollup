public without sharing virtual class RollupSObjectUpdater {
  @TestVisible
  private static String UPDATER_NAME = 'RollupCustomUpdater';
  @TestVisible
  private static final String DISPATCH_NAME = 'RollupDispatch';
  private static final SObjectSorter SORTER = new SObjectSorter();

  private final Schema.SObjectField fieldToken;
  private final List<IDispatcher> dispatchers;
  private final RollupPlugin plugin;

  private Boolean forceSyncUpdate = false;
  private RollupControl__mdt rollupControl;

  public interface IDispatcher {
    void dispatch(List<SObject> records);
  }

  public interface IUpdater {
    void performUpdate(List<SObject> recordsToUpdate, Database.DMLOptions options);
  }

  public RollupSObjectUpdater() {
    this.plugin = new RollupPlugin();
    this.dispatchers = this.fillDispatchers();
  }

  public RollupSObjectUpdater(Schema.SObjectField fieldToken) {
    this.fieldToken = fieldToken;
  }

  public void addRollupControl(RollupControl__mdt rollupControl) {
    this.rollupControl = rollupControl;
  }

  public void forceSyncUpdate() {
    this.forceSyncUpdate = true;
  }

  public virtual void doUpdate(List<SObject> recordsToUpdate) {
    if (this.forceSyncUpdate == false && Rollup.hasExceededCurrentRollupLimits(this.rollupControl)) {
      this.performAsyncUpdate(recordsToUpdate);
      return;
    }
    this.splitUpdates(recordsToUpdate);
    // typically I wouldn't advocate for the use of a guard clause here since an empty list
    // getting updated is a no-op, but the addition of the logging item is annoying ...
    if (recordsToUpdate.isEmpty() == false) {
      RollupLogger.Instance.log('updating the following records:', recordsToUpdate, LoggingLevel.FINE);
      SORTER.sort(recordsToUpdate);
      Database.DMLOptions dmlOptions = new Database.DMLOptions();
      dmlOptions.AllowFieldTruncation = true;
      if (this.rollupControl.ShouldDuplicateRulesBeIgnored__c != false) {
        dmlOptions.DuplicateRuleHeader.AllowSave = true;
      }
      this.winnowRecords(recordsToUpdate);
      this.updateRecords(recordsToUpdate, dmlOptions);
      this.dispatch(recordsToUpdate);
    }
  }

  public void updateField(SObject record, Object value) {
    this.updateValue(record, value);
  }

  private void updateValue(SObject record, Object value) {
    Schema.DisplayType fieldType = this.fieldToken.getDescribe().getType();

    if (value instanceof Decimal && fieldType == DisplayType.INTEGER) {
      Decimal decimalValue = (Decimal) value;
      value = decimalValue.intValue();
    } else {
      Boolean valueIsString = value instanceof String;
      switch on fieldType {
        when STRING, TEXTAREA {
          if (valueIsString == false) {
            value = String.valueOf(value);
          }
        }
        when DATETIME {
          if (valueIsString) {
            value = Datetime.parse((String) value);
          }
        }
        when Date {
          if (value instanceof Datetime) {
            value = ((Datetime) value).dateGmt();
          } else if (valueisString) {
            value = Date.parse((String) value);
          }
        }
      }
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

  private void splitUpdates(List<SObject> recordsToUpdate) {
    if (this.rollupControl.MaxParentRowsUpdatedAtOnce__c < recordsToUpdate.size() && this.forceSyncUpdate == false) {
      Integer maxIndexToRemove = recordsToUpdate.size() / 2;
      List<SObject> asyncUpdateList = new List<SObject>();
      while (recordsToUpdate.size() > maxIndexToRemove) {
        asyncUpdateList.add(recordsToUpdate.remove(recordsToUpdate.size() - 1));
      }
      this.performAsyncUpdate(asyncUpdateList);
    }
  }

  private void performAsyncUpdate(List<SObject> recordsToUpdate) {
    if (Limits.getLimitQueueableJobs() > Limits.getQueueableJobs() && recordsToUpdate.isEmpty() == false) {
      System.enqueueJob(new RollupAsyncSaver(recordsToUpdate, this.rollupControl));
    }
  }

  private void winnowRecords(List<SObject> records) {
    for (Integer index = records.size() - 1; index >= 0; index--) {
      Set<String> populatedFields = records.get(index).getPopulatedFieldsAsMap().keySet();
      if (populatedFields.size() == 1 && populatedFields.contains('Id')) {
        records.remove(index);
      } else if (
        RollupCurrencyInfo.isMultiCurrency() &&
        populatedFields.isEmpty() == false &&
        new Set<String>{ 'Id', RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME }.containsAll(populatedFields)
      ) {
        records.remove(index);
      }
    }
  }

  private void updateRecords(List<SObject> recordsToUpdate, Database.DMLOptions options) {
    RollupPlugin__mdt updaterPlugin = new RollupPlugin().getInstance(UPDATER_NAME);
    Type updaterType = updaterPlugin != null ? Type.forName(updaterPlugin.DeveloperName) : DefaultUpdater.class;
    ((IUpdater) updaterType.newInstance()).performUpdate(recordsToUpdate, options);
    this.forceSyncUpdate = false;
  }

  private class SObjectSorter extends RollupComparer {
    public override Integer compare(Object first, Object second) {
      Integer returnVal = 0;
      if (first instanceof SObject && second instanceof SObject) {
        String firstSObjectType = String.valueOf(((SObject) first).getSObjectType());
        String secondSObjectType = String.valueOf(((SObject) second).getSObjectType());
        if (firstSObjectType > secondSObjectType) {
          returnVal = this.moveTowardBackOfList;
        } else if (secondSObjectType > firstSObjectType) {
          returnVal = this.moveTowardFrontOfList;
        }
      }
      return returnVal;
    }
  }

  private class RollupAsyncSaver implements System.Queueable {
    private final List<SObject> records;
    private final RollupControl__mdt control;
    public RollupAsyncSaver(List<SObject> records, RollupControl__mdt control) {
      this.records = records;
      this.control = control;
    }

    public void execute(System.QueueableContext qc) {
      System.attachFinalizer(new RollupFinalizer());
      RollupSObjectUpdater updater = new RollupSObjectUpdater();
      updater.addRollupControl(this.control);
      new RollupSObjectUpdater().doUpdate(this.records);
    }
  }

  private without sharing class DefaultUpdater implements IUpdater {
    @SuppressWarnings('PMD.ApexCrudViolation')
    public void performUpdate(List<SObject> recordsToUpdate, Database.DMLOptions options) {
      Database.update(recordsToUpdate, options);
    }
  }
}
