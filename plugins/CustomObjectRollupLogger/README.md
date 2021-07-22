# Custom Object Rollup Logger

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04t6g000008SgtwAAC">
  <img alt="Deploy to Salesforce"
       src="../../media/deploy-package-to-prod.png">
</a>

<a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04t6g000008SgtwAAC">
  <img alt="Deploy to Salesforce Sandbox"
       src="../../media/deploy-package-to-sandbox.png">
</a>

To install this plugin and get it setup within your org properly:

1. Install the unmanaged package via the buttons above
2. Navigate to the Rollup `Org Defaults` Rollup Control record (Setup -> Custom Metadata Types -> Manage Records next to Rollup Control -> Org Defaults)
3. Enter `RollupCustomObjectLogger` into the `Rollup Logger Name` field, and ensure `Is Rollup Logging Enabled?` is checked off

That's it! Logs will now start flowing through on all rollup operations to `RollupLog__c`. A permission set, `Rollup Log Viewer` is included so that you can grant Rollup Log access to users other than yourself (should you be so inclined).

---

A utility class, `RollupLogBatchPurger` is included. By scheduling this class, you ensure that the default behavior of logs being deleted every **5** days occurs. This is to ensure the logs don't end up eating too much into your storage limits; you can customize the retention period for logs by customizing the `Days Rollup Logs Retained (Plugins Only)` field back on the `Custom Object Rollup Logger` Rollup Control record included with this plugin. To schedule via Anonymous Apex, a static helper function is included:

```java
// example cronSchedule string for running the purger every day at 7 AM:
// 0 0 7 ? * *
Id jobId = RollupLogBatchPurger.schedule(String jobName, String cronSchedule)
// the "jobId" returned is associated with the CronTrigger object
// which represents a scheduled job
```

The batch size for the scheduled job is also determined by the `Custom Object Rollup Logger` Rollup Control record's `Batch Chunk Size` field (defaults to 2000).