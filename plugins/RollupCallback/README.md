# Rollup Callback Plugin

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04t6g000008ShPqAAK">
  <img alt="Deploy to Salesforce"
       src="../../media/deploy-package-to-prod.png">
</a>

<a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04t6g000008ShPqAAK">
  <img alt="Deploy to Salesforce Sandbox"
       src="../../media/deploy-package-to-sandbox.png">
</a>

## Usage

Once you have the plugin installed, you have multiple options for interacting with the updated parent-level records.

1. Let the vanilla `RollupDispatch` implementation fire off a platform event (`RollupCallbackEvent__e`) which you can listen for and respond to in Apex, Flows, LWC, etc ... this platform event includes a field, `RecordIds__c` that contains a comma-separated list of all the updated parent records. This event fires by default any time record updates through `Rollup` are made, but can be prevented from firing by:

- deleting the `Should Fire Platform Event` Rollup Plugin Parameter associated with the `Rollup Dispatcher` Rollup Plugin CMDT record
- updating said record's `Value` field to `false`

A fun and very small possible addition to many record flexipages would be a screen flow that listened for Rollup Callback Events and, if the record Id matched one of the Ids in the comma-separated list, would serve up a warning to people on that page that rollup fields had been updated. The sky's the limit! ☀😎

2. You can also chose to add your own callback implementations by adding additional `Rollup Plugin Parameter` entries off of the `Rollup Dispatcher for Rollup Callback` Rollup Plugin Custom Metadata record. To do so, implement the `RollupSObjectUpdater.IDispatcher` interface:

```java
public interface RollupSObjectUpdater.IDispatcher {
  void dispatch(List<SObject> records);
}
```

Implementing this interface gives you something that the Rollup Callback Event can't - direct access to the parent records _and_ their updated rollup fields.

Here's an example implementation that fires off a subflow for you where:
- `SubflowRollupDispatcher` would be the Value filled out on a new `Rollup Plugin Parameter` associated with the `Rollup Dispatcher for Rollup Callback` Rollup Plugin CMDT record
- you had a subflow set up called `RollupSubflow` that had a collection input variable called `records` which conformed to an Apex-Defined Type, `SObjectDecorator` (note: this is a somewhat contrived example; it's my hope that Flows will support generic SObjects as input parameters within the next few releases)

```java
public class SObjectDecorator {
  @AuraEnabled
  public String SObjectName;
  @AuraEnabled
  public String RecordId;
  @AuraEnabled
  List<String> FieldNames;
}
public class SubflowRollupDispatcher implements RollupSObjectUpdater.IDispatcher {

  public void dispatch(List<SObject> records) {
    List<SObjectDecorator> wrappedRecords = new List<SObjectDecorator>();
    for (SObject record : records) {
      SObjectDecorator decorator = new SObjectDecorator();
      decorator.SObjectName = record.getSObjectType().getDescribe().getName();
      decorator.RecordId = record.Id;
      decorator.FieldNames = new List<String>(record.getPopulatedFieldsAsMap().keySet());
      wrappedRecords.add(decorator);
    }
    Flow.Interview rollupSubflow = Flow.Interview.RollupSubflow(
      new Map<String, Object>{
        'records' => records
      }
    );
    rollupSubflow.start();
  }
}
```