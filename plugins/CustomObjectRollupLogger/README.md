# Custom Object Rollup Logger

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04t6g000008SjqIAAS">
  <img alt="Deploy to Salesforce"
       src="../../media/deploy-package-to-prod.png">
</a>

<a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04t6g000008SjqIAAS">
  <img alt="Deploy to Salesforce Sandbox"
       src="../../media/deploy-package-to-sandbox.png">
</a>

To install this plugin and get it setup within your org properly:

1. Install the unmanaged package via the buttons above
2. Navigate to the Rollup Plugin CMDT (Setup -> Custom Metadata Types -> Manage Records next to Rollup Plugin -> New)
3. (This should already be done for you, upon install, but always good to double-check) - Enter `RollupCustomObjectLogger` into the `Rollup Plugin Name` field, choose the `Org_Default` rollup control record (and ensure `Is Rollup Logging Enabled?` is checked off on that record); the label can be whatever you'd like

That's it! Logs will now start flowing through on all rollup operations to `RollupLog__c`. A permission set, `Rollup Log Viewer` is included so that you can grant Rollup Log access to users other than yourself (should you be so inclined). You can use the included `Rollup Plugin Parameter` CMDT record `Custom Logging Debug Level` to fine-tune the logging level you'd like to use. Valid entries conform to the `System.LoggingLevel` enum: ERROR, WARN, INFO, DEBUG, FINE, FINER, FINEST. FINEST provides the highest level of detail; ERROR provides the least.

---

A utility class, `RollupLogBatchPurger` is included. By scheduling this class, you ensure that the default behavior of logs being deleted every **5** days occurs. This is to ensure the logs don't end up eating too much into your storage limits; you can customize the retention period for logs by customizing the `Days Rollup Logs Retained` field on the `Rollup Plugin Parameter` CMDT record included with this plugin. To schedule via Anonymous Apex, a static helper function is included:

```java
// example cronSchedule string for running the purger every day at 7 AM:
String cronSchedule = '0 0 7 ? * *';
String jobName = 'Rollup Custom Logger Batch Purger';
Id jobId = RollupLogBatchPurger.schedule(jobName, cronSchedule);
// the "jobId" returned is associated with the CronTrigger object
// which represents a scheduled job
```

The batch size for the scheduled job is also determined by the `Org_Default` Rollup Control record's `Batch Chunk Size` field (defaults to 2000).
