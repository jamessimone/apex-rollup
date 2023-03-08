@IsTest
private class RollupFlowFullRecalcDispatcherTests {
  @TestSetup
  static void setup() {
    Account acc = new Account(Name = RollupFlowFullRecalcDispatcherTests.class.getName());
    insert acc;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixCMDT', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    upsert new RollupSettings__c(IsEnabled__c = true);
  }

  @IsTest
  static void returnsSensibleErrorWhenDeveloperNameStringNotFilledOut() {
    List<RollupFlowFullRecalcDispatcher.FlowInput> flowInputs = new List<RollupFlowFullRecalcDispatcher.FlowInput>();
    RollupFlowFullRecalcDispatcher.FlowInput input = new RollupFlowFullRecalcDispatcher.FlowInput();
    flowInputs.add(input);

    Exception ex;
    try {
      RollupFlowFullRecalcDispatcher.performFullRecalcRollups(flowInputs);
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals('Comma-separated list of Rollup__mdt DeveloperName(s) was not provided', ex?.getMessage());
  }

  @IsTest
  static void shouldPerformCMDTFullRecalcFromFlowInput() {
    Rollup.onlyUseMockMetadata = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        DeveloperName = 'Dummy_Account_Revenue_Rollup',
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'PreferenceRank = 1'
      ),
      new Rollup__mdt(
        DeveloperName = 'Dummy_Account_Number_Of_Employees_Rollup',
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupOperation__c = 'COUNT',
        CalcItemWhereClause__c = 'Name = \'oneCMDT\''
      )
    };

    Test.startTest();
    RollupFlowFullRecalcDispatcher.performFullRecalcRollups(getFlowInputs(Rollup.rollupMetadata));
    Test.stopTest();

    Account acc = [SELECT AnnualRevenue, NumberOfEmployees FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals(1, acc.NumberOfEmployees);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @IsTest
  static void supportsMultipleChildrenTypesAtOnce() {
    Account acc = [SELECT Id FROM Account];

    Rollup.onlyUseMockMetadata = true;
    Rollup__mdt cpaMeta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      CalcItemWhereClause__c = 'PreferenceRank = 1',
      DeveloperName = 'Dummy_Account_Revenue_Rollup',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      LookupObject__c = 'Account',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      RollupOperation__c = 'SUM'
    );
    Rollup__mdt taskMeta = new Rollup__mdt(
      CalcItem__c = 'Task',
      CalcItemWhereClause__c = 'Subject != null',
      DeveloperName = 'Dummy_Account_Task_Rollup',
      LookupFieldOnCalcItem__c = 'WhatId',
      LookupFieldOnLookupObject__c = 'Id',
      LookupObject__c = 'Account',
      RollupFieldOnCalcItem__c = 'CallDurationInSeconds',
      RollupFieldOnLookupObject__c = 'NumberOfEmployees',
      RollupOperation__c = 'MIN'
    );
    Rollup.rollupMetadata = new List<Rollup__mdt>{ cpaMeta, taskMeta };

    insert new List<Task>{
      new Task(WhatId = acc.Id, CallDurationInSeconds = 5, Subject = 'Winner', ActivityDate = System.today()),
      new Task(WhatId = acc.Id, CallDurationInSeconds = 6, Subject = 'Not Min', ActivityDate = System.today())
    };

    List<RollupFlowFullRecalcDispatcher.FlowInput> flowInputs = new List<RollupFlowFullRecalcDispatcher.FlowInput>();
    flowInputs.addAll(getFlowInputs(new List<Rollup__mdt>{ cpaMeta }));
    flowInputs.addAll(getFlowInputs(new List<Rollup__mdt>{ taskMeta }));

    Test.startTest();
    RollupFlowFullRecalcDispatcher.performFullRecalcRollups(flowInputs);
    Test.stopTest();

    acc = [SELECT AnnualRevenue, NumberOfEmployees FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals(5, acc.NumberOfEmployees);
  }

  private static List<RollupFlowFullRecalcDispatcher.FlowInput> getFlowInputs(List<Rollup__mdt> metas) {
    List<RollupFlowFullRecalcDispatcher.FlowInput> flowInputs = new List<RollupFlowFullRecalcDispatcher.FlowInput>();
    RollupFlowFullRecalcDispatcher.FlowInput input = new RollupFlowFullRecalcDispatcher.FlowInput();
    input.rollupDeveloperNames = '';
    for (Rollup__mdt meta : metas) {
      input.rollupDeveloperNames += meta.DeveloperName + ',';
    }
    input.rollupDeveloperNames = input.rollupDeveloperNames.removeEnd(',');
    flowInputs.add(input);
    return flowInputs;
  }
}
