# Nebula Logger Plugin for Apex Rollup

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04t6g000008SgnEAAS">
  <img alt="Deploy to Salesforce"
       src="../../media/deploy-package-to-prod.png">
</a>

<a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04t6g000008SgnEAAS">
  <img alt="Deploy to Salesforce Sandbox"
       src="../../media/deploy-package-to-sandbox.png">
</a>

To install this plugin and get it setup within your org properly:

1. Install the unmanaged package via the buttons above
2. Navigate to the Rollup `Org Defaults` Rollup Control record (Setup -> Custom Metadata Types -> Manage Records next to Rollup Control -> Org Defaults)
3. Enter `RollupNebulaLoggerAdapater` into the `Rollup Logger Name` field, and ensure `Is Rollup Logging Enabled?` is checked off

That's it! Logs will now start flowing through on all rollup operations to `Log__c`, as they would with any other logging being done by Nebula.