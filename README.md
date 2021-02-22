# Apex Rollup

<a href="https://githubsfdeploy.herokuapp.com">
  <img alt="Deploy to Salesforce"
       src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

Create fast, scalable custom rollups driven by Custom Metadata in your Salesforce org with `Rollup`. As seen on [Replacing DLRS With Custom Rollup](https://www.jamessimone.net/blog/joys-of-apex/replacing-dlrs-with-custom-rollup/)!

## Usage

You have several different options when it comes to making use of `Rollup`:

- The Custom Metadata-driven solution: install with _one line of code_
- From Flow / Process builder using [the included invocable action](#flow-process-builder-invocable)
- [Via a scheduled job](#scheduled-jobs), created by running some Anonymous Apex
- [One-off jobs, kicked off via the `Rollup` app](#calculating-rollup-after-install)

### CMDT-based Rollup Solution:

All you need is one line of code in any trigger where you'd like to perform rollups to a "parent" object. If you were taking values from your Opportunity records and rolling some of them up to the Account, this single line would be put into your `Opportunity.trigger` file or within your Opportunity Handler class:

```java
// in a trigger. after insert, after update, and before delete are required
// to be listed on your trigger in order for this to work properly
Rollup.runFromTrigger();
```

Let me repeat: you **must** have the following contexts listed on your trigger:

```java
trigger ExampleTrigger on Opportunity(after insert, after update, before delete, after undelete) {
  Rollup.runFromTrigger();
  // etc. You can invoke the above from your handler if you have one
}
```

To be clear - the following trigger contexts are necessary when using `runFromTrigger` on any trigger installing `Rollup`:

- after insert
- after update
- before delete
- after undelete

That's it! Now you're ready to configure your rollups using Custom Metadata. `Rollup` makes heavy use of Entity Definition & Field Definition metadata fields, which allows you to simply select your options from within picklists, or dropdowns. This is great for giving you quick feedback on which objects/fields are available without requiring you to know the API name for every SObject and their corresponding field names.

#### Special Considerations For Use Of Custom Fields As Rollup/Lookup Fields

One **special** thing to note on the subject of Field Definitions — custom fields referenced in CMDT Field Definition fields are stored in an atypical way, and require the usage of additional SOQL queries as part of `Rollup`'s upfront cost. A typical `Rollup` operation will use `2` SOQL queries per rollup — the query that determines whether or not a job should be queued or batched, and a query for the specific Rollup Limit metadata (a dynamic query, which unfortunately means that it counts against the SOQL limits) — prior to going into the async context (where all limits are renewed) plus `1` SOQL qery (also dynamic, which is why it contributes even though it's querying CMDT). However, usage of custom fields as any of the four fields referenced in the `Rollup__mdt` custom metadata (details below) adds an additional SOQL query. If the SOQL queries used by `Rollup` becomes cause for concern, please [submit an issue](/issues) and we can work to address it!

#### Rollup Custom Metadata Field Breakdown

Within the `Rollup__mdt` custom metadata type, add a new record with fields:

- `Calc Item` - the SObject the calculation is derived from — in this case, Oppportunity
- `Lookup Object` - the SObject you’d like to roll the values up to (in this case, Account)
- `Rollup Field On Calc Item` - the field you’d like to aggregate (let's say Amount)
- `Lookup Field On Calc Item`- the field storing the Id or String referencing a unique value on another object (In the example, Id)
- `Lookup Field On Lookup Object` - the field on the lookup object that matches the value stored in `Lookup Field On Calc Item`
- `Rollup Field On Lookup Object` - the field on the lookup object where the rolled-up values will be stored (I've been using AnnualRevenue on the account as an example)
- `Rollup Operation` - A picklist field to select the operation you're looking to perform. Acceptable values are SUM / MIN / MAX / AVERAGE / COUNT / COUNT_DISTINCT / CONCAT / CONCAT_DISTINCT / FIRST / LAST. Both CONCAT and CONCAT_DISTINCT separate values with commas in the rollup field itself.
- `Rollup Control` - link to the Org Defaults for controlling rollups, or set a specific Rollup Control CMDT to be used with this rollup. Multiple rollups can be tied to one specific Control record, or simply use the Org Default record (included) for all of your rollups.
- `Changed Fields On Calc Item` (optional) - comma-separated list of field API Names to filter items from being used in the rollup calculations unless all the stipulated fields have changed
- `Full Recalculation Default Number Value` (optional) - for some rollup operations (SUM / COUNT-based operations in particular), you may want to start fresh with each batch of calculation items provided. When this value is provided, it is used as the basis for rolling values up to the "parent" record (instead of whatever the pre-existing value for that field on the "parent" is, which is the default behavior). **NB**: it's valid to use this field to override the pre-existing value on the "parent" for number-based fields, _and_ that includes Date / Datetime / Time fields as well. In order to work properly for these three field types, however, the value must be converted into UTC milliseconds. You can do this easily using Anonymous Apex, or a site such as [Current Millis](https://currentmillis.com/).
- `Full Recalculation Default String Value` (optional) - same as `Full Recalculation Default Number Value`, but for String-based fields (including Lookup and Id fields).
- `Calc Item Where Clause` (optional) - add conditions to filter the calculation items that are used. **Note** - the fields, especially parent-level fields, _must_ be present on the calculation items or the filtering will not work correctly. As of [v1.0.9](https://github.com/jamessimone/apex-rollup/tree/v1.0.9), nested conditionals (conditionals contained within parantheses are supported. However, due to the orthogonal nature of deeply nested conditionals from the original problem area, it's entirely possible that some forms of nested conditionals will not work, or will work in unintended ways. Please [submit an issue](/issues) if you are using Rollup and experience issues with calculation items correctly being flagged / not flagged toward the rollup field.
- `Is Full Record Set` (optional) - by default, if the records you are passing in comprise the full set of child items for a given lookup item but none of them "qualify" to be rolled up (either due to the use of the Calc Item Where Clause, Changed Fields On Calc Item, or a custom Evaluator), Rollup aborts early. If you know you have the exhaustive list of records to be used for a given lookup item **and** you stipulate the Full Recalculation Default Number (or String) Value, you can override the existing rollup item's amount by checking off this field
- `Order By (First/Last)` (optional) - at present, only valid when FIRST/LAST is used as the Rollup Operation. This is the API name of a text/date/number-based field that you would like to order the calculation items by. **Note** unlike DLRS, this field is _not_ optional on a first/last operation; a validation rule will enforce that you supply a value here, even if the value used is the same as the field you are rolling up on.

You can perform have as many rollups as you'd like per object/trigger — all operations are boxcarred together for optimal efficiency.

#### Notes On The Use Of CMDT To Control Your Rollups

There are two limitations to Entity Definition relationships that currently exist:

1. They cannot refer to the User object
2. They cannot refer to the Task/Event objects

For rollups referring to these objects, you can use either the Invocable or the static methods exposed on `Rollup` from Apex to roll values up.

#### Establishing Org Limits For Rollup Operations

When you install `Rollup`, you get two custom metadata types - `Rollup__mdt`, describe above, and `RollupControl__mdt`. The latter can be used in three different ways:

1. if you're using the CMDT trigger-based approach highlighted above to manage your rollups, you can tie the `RollupControl` record to an individual `Rollup` record
2. if you're using an invocable/scheduled/custom Apex-based approach, you can use specific patterns to match on the rollup being performed
3. you can use the included Rollup Control with API Name `Org_Defaults` to specify master-level overrides for all your rollups

These are the fields on the `Rollup Control` custom metadata type:

- `Max Lookup Rows Before Batching` - if you are rolling up to an object that interacts in many different ways within the system, `Rollup` moves from using a Queueable based system (read: fast and light) to a Batched Apex approach (read: solid, sometimes slow). You can override the default for switching to Batch Apex by lowering the number of rows. Without an `Org_Default` record, this defaults to `3333`
- `Max Lookup Rows For Queueable` - if you haven't selected a Batch Apex override, defaults to `5000`
- `Rollup` lookup field to the `Rollup__mdt` metadata record. Optional.
- `Should Abort Run` - if done at the `Org_Defaults` level, completely shuts down all rollup operations in the org. Otherwise, can be used on an individual rollup basis to turn on/off.
- `Should Run As` - a picklist dictating the preferred method for running rollup operations. Possible values are `Queueable`, `Batchable`, or `Synchronous Rollup`.
- `Trigger Or Invocable Name` - If you are using custom Apex, a schedulable, or rolling up by way of the Invocable action and can't use the `Rollup` lookup field. Use the pattern `trigger_fieldOnCalcItem_to_rollupFieldOnTarget_rollup` - for example: 'trigger_opportunity_stagename_to_account_name_rollup' (use lowercase on the field names). If there is a matching Rollup Limit record, those rules will be used. The first part of the string comes from how a rollup has been invoked - either by `trigger`, `invocable`, or `schedule`. A scheduled flow still uses `invocable`!

### Flow / Process Builder Invocable

<div id="flow-process-builder-invocable"></div>

I will touch only on Flows given that all indications from Salesforce would lead a person to believe they are the future of the "clicks" part in "clicks versus code":

Invoking the `Rollup` process from a Flow, in particular, is a joy; with a Record Triggered Flow, you can do the up-front processing to take in only the records you need, and then dispatch the rollup operation to the `Rollup` invocable:

![Example flow](./media/joys-of-apex-rollup-flow.png 'Fun and easy rollups from Flows')

This is also the preferred method for scheduling; while I do expose the option to schedule a rollup from Apex, I find the ease of use in creating Scheduled Flows in conjunction with the deep power of properly configured Invocables to be much more scalable than the "Scheduled Jobs" of old. This also gives you the chance to do some truly crazy rollups — be it from a Scheduled Flow, an Autolaunched Flow, or a Platform Event-Triggered Flow. As long as you can manipulate data to correspond to the shape of an existing SObject's fields, they don't even have to exist; you could have an Autolaunched flow rolling up records when invoked from a REST API so long as the data you're consuming contains a String/Id matching something on the "parent" rollup object.

Here are the arguments necessary to invoke `Rollup` from a Flow / Process Builder:

- `Object for "Records To Rollup" (input)` - comes from your calculation items, and their SObject type should be selected accordingly. If you are rolling up from Opportunity to Account, you would select Opportunity as the type
- `Records To Rollup` - a collection of SObjects. These need to be stored in a collection variable
- `Calc Item Rollup Field` - the API Name of the field you’d like to aggregate (let's say Amount)
- `Lookup Field On Calc Item`- the API Name of the field storing the Id or String referencing a unique value on another object (In the example, Id)
- `Lookup Field On Lookup Object` - the API Name of the field on the lookup object that matches the value stored in `Lookup Field On Calc Item`
- `Rollup Field On Lookup Object` - the API Name of the field on the lookup object where the rolled-up values will be stored (I've been using AnnualRevenue on the account as an example)
- `Rollup Context` - INSERT / UPSERT / UPDATE / DELETE
- `Rollup Operation` - the operation you're looking to perform. Acceptable values are SUM / MIN / MAX / AVERAGE / COUNT / COUNT_DISTINCT / CONCAT / CONCAT_DISTINCT / FIRST / LAST. Both CONCAT and CONCAT_DISTINCT separate values with commas
- `Calc item changed fields` (optional) - comma-separated list of field API Names to filter items from being used in the rollup calculations unless all the stipulated fields have changed
- `Full Recalculation Default Number Value` (optional) - for some rollup operations (SUM / COUNT-based operations in particular), you may want to start fresh with each batch of calculation items provided. When this value is provided, it is used as the basis for rolling values up to the "parent" record (instead of whatever the pre-existing value for that field on the "parent" is, which is the default behavior). **NB**: it's valid to use this field to override the pre-existing value on the "parent" for number-based fields, _and_ that includes Date / Datetime / Time fields as well. In order to work properly for these three field types, however, the value must be converted into UTC milliseconds. You can do this easily using Anonymous Apex, or a site such as [Current Millis](https://currentmillis.com/).
- `Full Recalculation Default String Value` (optional) - same as `Full Recalculation Default Number Value`, but for String-based fields (including Lookup and Id fields).
- `SOQL Where Clause To Exclude Calc Items` (optional) - add conditions to filter the calculation items that are used. **Note** - the fields, especially parent-level fields, _must_ be present on the calculation items or the filtering will not work correctly.
- `Is Full Record Set` (optional) - by default, if the records you are passing in comprise the full set of child items for a given lookup item but none of them "qualify" to be rolled up (either due to the use of the Calc Item Where Clause, Changed Fields On Calc Item, or a custom Evaluator), Rollup aborts early. If you know you have the exhaustive list of records to be used for a given lookup item **and** you stipulate the Full Recalculation Default Number (or String) Value, you can override the existing rollup item's amount by toggling this field
- `Order By (First/Last)` (optional) - at present, only valid when FIRST/LAST is used as the Rollup Operation. This is the API name of a text/date/number-based field that you would like to order the calculation items by. **Note** unlike DLRS, this field is _not_ optional on a first/last operation; a validation rule will enforce that you supply a value here, even if the value used is the same as the field you are rolling up on.

Unfortunately, the "Description" section for Invocable fields does not show up as help text within the Flow Builder, but hopefully it's clear how each property should be configured!

#### Considerations For Scheduled Flows

In order to prevent blowing through the Flow Interview limit for each day, it's important to note that the use of `Rollup` with a specific SObject in the scheduled flow's start node will run a flow interview for _every_ record retrieved. However, if the scheduled flow is run without a specific SObject having been selected in the start node, the process is bulkified successfully and you only consume a single flow interview per batch of records.

### Calculating Rollups After Install

<div id="calculating-rollup-after-install"></div>

Use the included app and permission set (`See Rollup App`) permission set to uncover the `Rollup` app - a single-page-application where you can manually kick off rollup jobs. This is important because `Rollup` works on an ongoing basis; in order for your rollups to be correct, unless the child object you're starting to rollup has now rows when you implement `Rollup`, a one-off full recalculation is necessary. Here's how you would fill out the page to get things started:

![Example of Rollup App](./media/joys-of-apex-rollup-app.png 'Manually kicking off rollup jobs')

### Scheduled Jobs

<div id="scheduled-jobs"></div>

I would _highly_ recommend scheduling through Scheduled Flows.

That being said, `Rollup` exposes the option to use Scheduled Jobs if that's more your style. You can use the following Anonymous Apex script to schedule rollups:

```java
// Method signature: (String jobName, String cronExp, String query, List<Id> rollupMetadataIds, Evaluator eval)
Rollup.schedule(
  'My example job name',
  'my cron expression, like 0 0 0 * * ?',
  'my SOQL query, like SELECT Id, Amount FROM Opportunity WHERE CreatedDate > YESTERDAY',
  new List<Id>{ 'The ids of Rollup__mdt records configuring the rollup operation' },
  null
);
```

That last argument - the `null` value - has to implement an interface called `Evaluator` (or it can just be left null). More on that below.

## Custom Apex Rollups

If the CMDT-based or other solutions won't cut it and you need more customizability, there's an extensive API surface exposed by `Rollup` using public static helper methods:

```java
// you can batch rollup operations into one!
Rollup.batch(
  Rollup.countDistinctFromApex(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.NumberOfEmployees, Account.SObjectType),
  Rollup.sumFromApex(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType)
);

// you could even batch multiple batches (not sure why you would do this, but it's technically supported!!)
Rollup.batch(
  Rollup.batch(
    // ... it's batches all the way down!
    Rollup.countDistinctFromApex(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.NumberOfEmployees, Account.SObjectType),
    Rollup.sumFromApex(Opportunity.Amount, Opportunity.AccountId, Account.Id, Account.AnnualRevenue, Account.SObjectType)
  ),
  // don't actually do this, please
  Rollup.average(Opportunity.CloseDate, Opportunity.Id, Lead.ConvertedDate, Lead.ConvertedOpportunityId, Lead.SObjectType)
)
```

The following methods are exposed:

```java
// in Rollup.cls

public static void batch(Rollup rollup, Rollup secondRollup)
public static void batch(Rollup rollup, Rollup secondRollup, Rollup thirdRollup)
public static void batch(List<Rollup> rollups)
public static Rollup runCalc() // more on this method below

public static Rollup averageFromApex(
  SObjectField averageFieldOnCalcItem,
  SObjectField lookupFieldOnCalcItem,
  SObjectField lookupFieldOnOperationObject,
  SObjectField averageFieldOnOperationObject,
  SObjectType lookupSobjectType
)

public static Rollup countDistinctFromApex(
  SObjectField countDistinctFieldOnCalcItem,
  SObjectField lookupFieldOnCalcItem,
  SObjectField lookupFieldOnOperationObject,
  SObjectField countDistinctFieldOnOperationObject,
  SObjectType lookupSobjectType
)

public static Rollup concatFromApex(
  SObjectField concatFieldOnCalcItem,
  SObjectField lookupFieldOnCalcItem,
  SObjectField lookupFieldOnOperationObject,
  SObjectField concatFieldOnOperationObject,
  SObjectType lookupSobjectType
)

public static Rollup countFromApex(
  SObjectField countFieldOnCalcItem,
  SObjectField lookupFieldOnCalcItem,
  SObjectField lookupFieldOnOperationObject,
  SObjectField countFieldOnOperationObject,
  SObjectType lookupSobjectType
)

public static Rollup maxFromApex(
  SObjectField maxFieldOnCalcItem,
  SObjectField lookupFieldOnCalcItem,
  SObjectField lookupFieldOnOperationObject,
  SObjectField maxFieldOnOperationObject,
  SObjectType lookupSobjectType
)

public static Rollup minFromApex(
  SObjectField minFieldOnCalcItem,
  SObjectField lookupFieldOnCalcItem,
  SObjectField lookupFieldOnOperationObject,
  SObjectField minFieldOnOperationObject,
  SObjectType lookupSobjectType
)

public static Rollup sumFromApex(
  SObjectField sumFieldOnCalcItem,
  SObjectField lookupFieldOnCalcItem,
  SObjectField lookupFieldOnOperationObject,
  SObjectField sumFieldOnOpOject,
  SObjectType lookupSobjectType
)

// for using as the "one line of code" and CMDT-driven rollups
public static void runFromTrigger()

// the alternative one-liner for CDC triggers
// more on that in the CDC section of "Special Considerations", below
public static void runFromCDCTrigger()
```

All of the "...fromTrigger" methods shown above can also be invoked using a final argument, the `Evaluator`:

```java
public interface Evaluator {
  Boolean matches(Object calcItem);
}
```

By implementing this interface in a concrete class and then passing an instance of that class to `Rollup`, you can codify advanced business logic within Apex to drive which records classify for rollups:

```java
// assuming you are using this with opportunities:

public class OpportunityNameEvaluator implements Rollup.Evaluator {
  public Boolean matches(Object calcItem) {
    if((calcItem instanceof Opportunity) == false) {
      return false;
    }

    Opportunity opp = (Opportunity) calcItem;
    return opp.Name.contains('Business Development');
  }
}

// and an example usage:

Rollup.sumFromApex(
  Opportunity.Amount
  Opportunity.AccountId,
  Account.Id,
  Account.AnnualRevenue,
  Account.SObjectType,
  new OpportunityNameEvaluator()
).runCalc();
```

It's that simple. Note that in order for custom Apex solutions that don't use the `batch` static method on `Rollup` to properly start, the `runCalc()` method must also be called. That is, if you only have one rollup operation per object, you'll _always_ need to call `runCalc()` when invoking `Rollup` from a trigger.

Another note for when the use of an `Evaluator` class might be necessary — let's say that you have some slight lookup skew caused by a fallback object in a lookup relationship. This fallback object has thousands of objects tied to it, and updates to it are frequently painful / slow. If you didn't need the rollup for the fallback, you could implement an `Evaluator` to exclude it from being processed:

```java
// again using the example of Opportunities
trigger OpportunityTrigger on Opportunity(before update, after update, before insert, after insert, before delete) {

  Rollup.sumFromApex(
    Opportunity.Amount
    Opportunity.AccountId,
    Account.Id,
    Account.AnnualRevenue,
    Account.SObjectType,
    new FallbackAccountExcluder()
  ).runCalc();

  public class FallbackAccountExcluder implements Rollup.Evaluator {
    public Boolean matches(Object calcItem) {
      if((calcItem instanceof Opportunity) == false) {
        return false;
      }

      Opportunity opp = (Opportunity) calcItem;
      // there are so many ways you could avoid hard-coding the Id here:
      // custom settings, custom metadata, labels, and platform cache, to name a few
      return opp.AccountId == 'your fallback Account Id' ? false : true;
    }
  }
}
```

## Special Considerations

While pains have been taken to create a solution that's truly one-sized-fits-all, any professional working in the Salesforce ecosystem knows that it's difficult to make that the case for any product or service — even something open-source and forever-free, like `Rollup`. All of that is to say that while I have tested the hell out of `Rollup` and have used it already in production, your mileage may vary depending on what you're trying to do. Some operations that are explicitly not supported within the SOQL aggregate functions (like `SELECT MIN(ActivityDate) FROM Task`) are possible when using `Rollup`. Another example would be `MAX` or `MIN` operations on multi-select picklists. I don't know _why_ you would want to do that ... but you can!

### Picklists

Picklists are a loaded topic in Salesforce. They're not only dropdowns, but the order is supposed to matter! MIN/MAXING on a picklist is supposed to return the deepest possible entry in the picklist (for MAX), or the closest to the top of the picklist (for MIN). If you've studied the aggregate function documentation thoroughly in the Salesforce Developer Docs, this will comes as no surprise - but because the ranking system for picklist differs from the ranking system for other pieces of text, I thought to call it out specifically.

### Recalculations

One of the reasons that `Rollup` can boast of superior performance is that, for many operations, it can perform all of the rolling-up necessary without performing much in the way of queries. There are, as always, exceptions to that rule. "Recalculations" are triggered when certain rollup operations encounter something of interest:

- a MIN operation might find that one of the calculation items supplied to it previously _was_ the minimum value, but is no longer the minimum on an update
- a MAX operation might find that one of the calculation items supplied to it previously _was_ the _maxmimum_ value, but is no longer the max on an update
- ... pretty much any operation involving AVERAGE

In these instances, `Rollup` _does_ requery the calculation object; it also does another loop through the calculation items supplied to it in search of _all_ the values necessary to find the true rollup value. This provides context, more than anything — the rollup operation should still be lightning fast.

### Custom Apex

If you are implementing `Rollup` through the use of the static Apex methods instead of CMDT, one thing to be aware of — if you need to perform 6+ rollup operations _and_ you are rolling up to more than one target object, you should absolutely keep your rollups ordered by the target object when invoking the `batch` method:

```java
// this is perfectly valid
Rollup.batch(
  // repeated just for lack of having better examples, but let's say five separate rollups ....
  // the important part is that they're ordered by the last argument; the SObjectType in question
  Rollup.concatDistinctFromApex(Task.Status, Task.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType),
  Rollup.concatDistinctFromApex(Task.Status, Task.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType),
  Rollup.concatDistinctFromApex(Task.Status, Task.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType),
  Rollup.concatDistinctFromApex(Task.Status, Task.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType),
  Rollup.concatDistinctFromApex(Task.Status, Task.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType),
  Rollup.maxFromApex(Task.ActivityDate, Task.AccountId, Opportunity.AccountId, Opportunity.CloseDate, Opportunity.SObjectType)
)

// this should be avoided. It ** could ** potentially lead to a chunking error when updating all of the rollup fields
Rollup.batch(
  Rollup.concatDistinctFromApex(Task.Status, Task.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType),
  Rollup.maxFromApex(Task.ActivityDate, Task.AccountId, Opportunity.AccountId, Opportunity.CloseDate, Opportunity.SObjectType)
  Rollup.concatDistinctFromApex(Task.Status, Task.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType),
  Rollup.maxFromApex(Task.ActivityDate, Task.AccountId, Opportunity.AccountId, Opportunity.CloseDate, Opportunity.SObjectType)
  Rollup.concatDistinctFromApex(Task.Status, Task.AccountId, Account.Id, Account.AccountNumber, Account.SObjectType),
  Rollup.maxFromApex(Task.ActivityDate, Task.AccountId, Opportunity.AccountId, Opportunity.CloseDate, Opportunity.SObjectType)
);
```

### Change Data Capture (CDC)

As of [v1.0.4](https://github.com/jamessimone/apex-rollup/tree/v1.0.4), CDC _is_ supported. However, at the moment Change Data Capture can be used strictly through CMDT, and requires a different one-liner for installation into your CDC object Trigger:

```java
// within your CDC trigger, using Opportunity as an example:
trigger OpportunityChangeEventTrigger on OpportunityChangeEvent (after insert) {
  Rollup.runFromCDCTrigger();
}
```

Note that you're still selecting `Opportunity` as the `Calc Item` within your Rollup metadata record in this example; in fact, you cannot select `OpportunityChangeEvent`, so hopefully that was already clear. This means that people interested in using CDC should view it as an either/or option when compared to invoking `Rollup` from a standard, synchronous trigger. Additionally, that means reparenting that occurs at the calculation item level (the child object in the rollup operation) is not yet a supported feature of `Rollup` for CDC-based rollup actions — because the underlying object has already been updated in the database, and because CDC events only contain the new values for changed fields (instead of the new & old values). It's a TBD-type situation if this will ever be supported.

### Multi-Currency Orgs

Untested. I would expect that MAX/SUM/MIN/AVERAGE operations would have undefined behavior if mixed currencies are present on the children items. This would be a good first issue for somebody looking to contribute!

## Commit History & Contributions

This repository comes after the result of [dozens of commits](https://github.com/jamessimone/apex-mocks-stress-test/commits/rollup) on my working repository. You can view the full history of the evolution of `Rollup` there.

On the subject of contributing ([also covered in the Contributing doc](./Contributing.md)), I'm open to collaborating! Please make sure you install this repo's dependencies using NPM or Yarn:

```bash
yarn
# or
npm -i
```

I use Prettier in conjunction with the `prettier-apex` plugin for formatting Apex. There are (hopefully) minor stylistic choices that I have made and hope any contributors will respect when modifying the code:

- Format On Save. I let Prettier do all the heavy lifting
- Column length (set in `.prettierrc`) is set to `160`. That's a _little_ wide for laptop developers. I know, as I've spent a good portion of time on my personal Thinkpad working on this project. Still, for a desktop it's perfect for reducing lines of code. Forgive me.
- Spaces ... are .... set to `2`. Pretty unusual for Java-ish languages, but as I am looking to keep this all in one class, it really helped with increasing readability / reducing LOC

Further instructions for contributions are listed [in the Contributing doc](./Contributing.md). Please ensure the guidelines enumerated there are respected when submitting pull requests.

## Roadmap

Forthcoming. Drop me <a href="mailto:james@sheandjim.com" title="Email me">a line</a>, <a title="contact me" href="https://www.jamessimone.net/contact/">contact me online</a> or raise an issue here with questions.
