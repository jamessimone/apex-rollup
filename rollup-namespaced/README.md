# Namespaced Version Of Apex Rollup

This package contains the exact same source code as the unlocked Apex Rollup package; it's just created using the `please__` namespace. Special things to note:

- Flows that don't take advantage of the CMDT-based invocable action need to fully qualify the namespace for all namespaced fields. As an example a flow using a custom object called `Child__c` in the `please__` namespace with a custom field called `Text__c`:
  - would have the Child Object be specified as `please__Child__c`
  - would have the Rollup Object Calc Field be specified as `please__Text__c`
- Additionally, for both Flows **and** CMDT-driven rollups:
  - all Calc Item Where Clauses using namespaced fields need to have the namespace specified
  - same goes for any Grandparent Relationship Field Paths, as well as for any One To Many Grandparent Fields
- Just for the base Rollup invocable, the following also applies:
  - namespaced fields used as the Ultimate Parent need to have the namespace be fully qualified
  - namespaced fields used in the Order By field need to have the namespace be fully qualified

TL;DR - regardless of whether you're using Flow/CMDT to arrange your rollups with the namespaced version of Apex Rollup, any _text-based_ fields where you specify field references need to use their package's namespace to qualify the API names for fields/objects when that namespace differs from an org's default namespace.

For more info, see the base `README`.

## Deployment & Setup

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04t6g000008Off4AAC">
  <img alt="Deploy to Salesforce"
       src="./media/deploy-package-to-prod.png">
</a>

<a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04t6g000008Off4AAC">
  <img alt="Deploy to Salesforce Sandbox"
       src="./media/deploy-package-to-sandbox.png">
</a>
