# Nebula Logger Plugin for Apex Rollup

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04t6g000007zM6tAAE">
  <img alt="Deploy to Salesforce"
       src="../../media/deploy-package-to-prod.png">
</a>

<a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04t6g000007zM6tAAE">
  <img alt="Deploy to Salesforce Sandbox"
       src="../../media/deploy-package-to-sandbox.png">
</a>

To install this plugin and get it setup within your org properly:

1. Make sure you have Nebula Logger installed! The minimum version you should have is: `4.5.2`
2. Install the unmanaged package via the button(s) above
3. Navigate to the Rollup Plugin CMDT (Setup -> Custom Metadata Types -> Manage Records next to Rollup Plugin -> New)
4. (This should already be done for you, upon install, but always good to double-check) - Enter `RollupNebulaLoggerAdapter` into the `Rollup Plugin Name` field, choose the `Org_Default` rollup control record (and ensure `Is Rollup Logging Enabled?` is checked off on that record); the label can be whatever you'd like. At this time, there are no `Rollup Plugin Parameter` entries needed for this particular plugin.

That's it! Logs will now start flowing through on all rollup operations to `Log__c`, as they would with any other logging being done by Nebula.

## Apex Rollup-specific Log Info

A few points specific to Apex Rollup within your logs:

- `Log__c.Scenario__c` is set to `Apex Rollup`
- `LogEntry__c.OriginLocation__c` deliberately suppresses the logging classes in Apex Rollup so that the `OriginLocation__c` is properly reported as the first actual method called in Apex Rollup
