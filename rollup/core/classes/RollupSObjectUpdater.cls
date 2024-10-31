global without sharing virtual class RollupSObjectUpdater {
  @TestVisible
  private static String UPDATER_NAME = 'RollupCustomUpdater';
  @TestVisible
  private static String PRE_AND_POST_UPDATER_NAME = 'RollupPreAndPostUpdater';
  @TestVisible
  private static final String DISPATCH_NAME = 'RollupDispatch';
  private static final System.Comparator<SObject> SORTER = new SObjectTypeSorter();
  @TestVisible
  private static final Map<Id, SObject> RECORDS_TO_UPDATE = new Map<Id, SObject>();

  private final Schema.SObjectField fieldToken;
  private final List<IDispatcher> dispatchers;
  private final RollupPlugin plugin;

  private Boolean forceSyncUpdate = false;
  private RollupControl__mdt rollupControl;
  private RollupFinalizer finalizer;

  global interface IDispatcher {
    void dispatch(List<SObject> records);
  }

  global interface IUpdater {
    void performUpdate(List<SObject> recordsToUpdate, Database.DMLOptions options);
  }

  global interface IPrePostUpdater {
    void preUpdate(List<SObject> recordsToUpdate, Database.DMLOptions options);
    void postUpdate(List<SObject> recordsToUpate);
  }

  global RollupSObjectUpdater() {
    this.plugin = new RollupPlugin();
    this.dispatchers = this.fillDispatchers();
  }

  public void addRollupControl(RollupControl__mdt rollupControl) {
    this.rollupControl = rollupControl;
  }

  public void forceSyncUpdate() {
    this.forceSyncUpdate = true;
  }

  public RollupSObjectUpdater setFinalizer(RollupFinalizer finalizer) {
    this.finalizer = finalizer;
    return this;
  }

  public void updateRecords() {
    List<SObject> recordsToUpdate = RECORDS_TO_UPDATE.values();
    // static map has to be cleared BEFORE calling "doUpdate"
    // otherwise any cascading rollups on the parent will cause recursion here
    RECORDS_TO_UPDATE.clear();
    this.doUpdate(recordsToUpdate);
  }

  global virtual void doUpdate(List<SObject> recordsToUpdate) {
    if (this.forceSyncUpdate == false && Rollup.hasExceededCurrentRollupLimits(this.rollupControl)) {
      this.performAsyncUpdate(recordsToUpdate);
      return;
    }
    this.winnowRecords(recordsToUpdate);
    this.splitUpdates(recordsToUpdate);
    // typically I wouldn't advocate for the use of a guard clause here since an empty list
    // getting updated is a no-op, but the addition of the logging item is annoying ...
    if (recordsToUpdate.isEmpty() == false) {
      RollupLogger.Instance.log('updating ' + recordsToUpdate.size() + ' records', System.LoggingLevel.INFO);
      recordsToUpdate.sort(SORTER);
      Database.DMLOptions dmlOptions = new Database.DMLOptions();
      dmlOptions.AllowFieldTruncation = true;
      dmlOptions.OptAllOrNone = this.rollupControl.ShouldThrowOnSaveErrors__c;
      if (this.rollupControl.ShouldDuplicateRulesBeIgnored__c != false) {
        dmlOptions.DuplicateRuleHeader.AllowSave = true;
      }
      this.updateRecords(recordsToUpdate, dmlOptions);
      this.dispatch(recordsToUpdate);
    }
  }

  public void updateField(Schema.SObjectField fieldToken, SObject record, Object value) {
    Schema.DisplayType fieldType = fieldToken.getDescribe().getType();

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
        when DATE {
          if (value instanceof Datetime) {
            value = ((Datetime) value).dateGmt();
          } else if (valueisString) {
            value = Date.parse((String) value);
          }
        }
      }
    }
    SObject updateRecord = RECORDS_TO_UPDATE.get(record.Id);
    if (updateRecord == null) {
      updateRecord = record.getSObjectType().newSObject(record.Id);
      RECORDS_TO_UPDATE.put(record.Id, updateRecord);
    }
    record.put(fieldToken, value);
    updateRecord.put(fieldToken, value);
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
      RollupLogger.Instance.log('dispatching updated records to: ' + this.getLogString(this.dispatchers), System.LoggingLevel.FINE);
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
      RollupAsyncSaver saver = new RollupAsyncSaver(this, recordsToUpdate);
      if (this.finalizer == null) {
        saver.runCalc();
      } else {
        this.finalizer.addCaboose(saver);
      }
    }
  }

  private void winnowRecords(List<SObject> records) {
    for (Integer index = records.size() - 1; index >= 0; index--) {
      Set<String> populatedFields = records.get(index).getPopulatedFieldsAsMap().keySet();
      if (populatedFields.size() == 1 && populatedFields.contains('Id')) {
        records.remove(index);
      }
    }
  }

  private void updateRecords(List<SObject> recordsToUpdate, Database.DMLOptions options) {
    RollupPlugin__mdt updaterPlugin = this.plugin.getInstance(UPDATER_NAME);
    IUpdater updater = (IUpdater) this.getInstanceOrDefault(updaterPlugin?.DeveloperName, IUpdater.class, DefaultUpdater.class);
    IPrePostUpdater preAndPostUpdater = this.getPreAndPostUpdater();
    preAndPostUpdater?.preUpdate(recordsToUpdate, options);
    updater.performUpdate(recordsToUpdate, options);
    preAndPostUpdater?.postUpdate(recordsToUpdate);
    this.forceSyncUpdate = false;
  }

  private IPrePostUpdater getPreAndPostUpdater() {
    RollupPlugin__mdt preAndPostUpdaterPlugin = this.plugin.getInstance(PRE_AND_POST_UPDATER_NAME);
    List<RollupPluginParameter__mdt> parameters = this.plugin.getMatchingParameters(preAndPostUpdaterPlugin?.Id);
    String typeName;

    for (RollupPluginParameter__mdt param : parameters) {
      typeName = param.Value__c;
    }
    return (IPrePostUpdater) this.getInstanceOrDefault(typeName, IPrePostUpdater.class, null);
  }

  private Object getInstanceOrDefault(String typeName, Type desiredType, Type defaultType) {
    Type potentialType;
    if (typeName != null) {
      potentialType = Type.forName(typeName);
    }
    // Type.isAssignableFrom is great, but it throws instead of returning false for null
    if (potentialType != null && desiredType.isAssignableFrom(potentialType)) {
      return potentialType.newInstance();
    }
    return defaultType?.newInstance();
  }

  private class SObjectTypeSorter implements System.Comparator<SObject> {
    private final System.Comparator<String> innerSorter = new RollupFieldInitializer.StringSorter();
    public Integer compare(SObject first, SObject second) {
      return this.innerSorter.compare('' + first.getSObjectType(), '' + second.getSObjectType());
    }
  }

  private without sharing class RollupAsyncSaver extends RollupAsyncProcessor.QueueableProcessor {
    private final RollupSObjectUpdater saver;
    private RollupAsyncSaver(RollupSObjectUpdater saver, List<SObject> itemsToUpdate) {
      super(null, itemsToUpdate, null);
      this.finalizer = saver.finalizer;
      this.isNoOp = itemsToUpdate.isEmpty();
      saver.rollupControl.MaxParentRowsUpdatedAtOnce__c = 500;
      this.saver = saver;
    }

    public override String getTypeName() {
      return RollupAsyncSaver.class.getName();
    }

    public override String runCalc() {
      return System.enqueueJob(this);
    }

    public override Map<String, String> customizeToStringEntries(Map<String, String> props) {
      props.remove('Invocation Point');
      props.remove('Is Full Recalc');
      props.remove('Is Conductor');
      props.remove('Inner rollups');
      props.put('Async update size', '' + this.calcItems.size());
      return props;
    }

    protected override void performWork() {
      RollupLogger.Instance.log('Deferred async saving starting for parent records', new Map<Id, SObject>(this.calcItems).keySet(), System.LoggingLevel.INFO);
      this.saver.doUpdate(this.calcItems);
      RollupLogger.Instance.log('Saving finished', System.LoggingLevel.INFO);
      RollupLogger.Instance.save();
    }
  }

  private without sharing class DefaultUpdater implements IUpdater {
    @SuppressWarnings('PMD.ApexCrudViolation')
    public void performUpdate(List<SObject> recordsToUpdate, Database.DMLOptions options) {
      List<Database.SaveResult> results = Database.update(recordsToUpdate, options);
      for (Integer index = 0; index < results.size(); index++) {
        Database.SaveResult res = results[index];
        if (res.isSuccess() == false) {
          String flattenedErrorString = '';
          for (Database.Error err : res.getErrors()) {
            flattenedErrorString += err.getStatusCode() + ': ' + err.getMessage() + '\n';
          }

          RollupLogger.Instance.log(flattenedErrorString.removeEnd('\n'), recordsToUpdate[index], System.LoggingLevel.ERROR);
        }
      }
    }
  }

  @SuppressWarnings('PMD.ApexCrudViolation')
  global without sharing class PreAndPostUpdater implements IPrePostUpdater {
    public void preUpdate(List<SObject> records, Database.DMLOptions options) {
      RollupSettings__c settings = RollupSettings__c.getInstance();
      settings.BypassValidationRules__c = true;
      Database.upsert(settings, false);
    }

    public void postUpdate(List<SObject> records) {
      RollupSettings__c settings = RollupSettings__c.getInstance();
      settings.BypassValidationRules__c = false;
      Database.upsert(settings, false);
    }
  }
}
