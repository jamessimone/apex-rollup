@IsTest
private class RollupFlowFullRecalcDispatcherTests {
  @TestSetup
  static void setup() {
    Account acc = new Account(Name = RollupFlowFullRecalcDispatcherTests.class.getName());
    insert acc;

    upsert new RollupSettings__c(IsEnabled__c = true);

    insert new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixCMDT', ParentId = acc.Id, PreferenceRank = 1)
    };
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
    Account acc = [SELECT Id FROM Account];
    List<ContactPointAddress> cpas = [SELECT Id, PreferenceRank, Name FROM ContactPointAddress];

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
        CalcItemWhereClause__c = 'PreferenceRank = ' + cpas[0].PreferenceRank
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
        CalcItemWhereClause__c = 'Name = \'' + cpas[0].Name + '\''
      )
    };

    String flowInputString = 'Dummy_Account_Revenue_Rollup, Dummy_Account_Number_Of_Employees_Rollup';
    List<RollupFlowFullRecalcDispatcher.FlowInput> flowInputs = new List<RollupFlowFullRecalcDispatcher.FlowInput>();
    RollupFlowFullRecalcDispatcher.FlowInput input = new RollupFlowFullRecalcDispatcher.FlowInput();
    input.rollupDeveloperNames = flowInputString;
    flowInputs.add(input);

    Test.startTest();
    Rollup.onlyUseMockMetadata = true;
    RollupFlowFullRecalcDispatcher.performFullRecalcRollups(flowInputs);
    Test.stopTest();

    acc = [SELECT AnnualRevenue, NumberOfEmployees FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals(1, acc.NumberOfEmployees);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @IsTest
  static void refinesQueryWhenOptionalRecordsAreSupplied() {
    Rollup.onlyUseMockMetadata = true;
    Account acc = [SELECT Id FROM Account];
    Account secondParent = new Account(Name = 'Second Parent');
    insert secondParent;
    List<ContactPointAddress> cpas = [SELECT Id, PreferenceRank, Name FROM ContactPointAddress];
    ContactPointAddress excludedCpa = cpas.remove(cpas.size() - 1);
    excludedCpa.ParentId = secondParent.Id;
    update excludedCpa;

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
        CalcItemWhereClause__c = 'PreferenceRank = ' + cpas[0].PreferenceRank
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
        CalcItemWhereClause__c = 'Name = \'' + cpas[0].Name + '\''
      )
    };

    String flowInputString = 'Dummy_Account_Revenue_Rollup, Dummy_Account_Number_Of_Employees_Rollup';
    List<RollupFlowFullRecalcDispatcher.FlowInput> flowInputs = new List<RollupFlowFullRecalcDispatcher.FlowInput>();
    RollupFlowFullRecalcDispatcher.FlowInput input = new RollupFlowFullRecalcDispatcher.FlowInput();
    input.rollupDeveloperNames = flowInputString;
    input.rollupRecords = cpas;
    flowInputs.add(input);

    Test.startTest();
    RollupFlowFullRecalcDispatcher.performFullRecalcRollups(flowInputs);
    Test.stopTest();

    acc = [SELECT AnnualRevenue, NumberOfEmployees FROM Account WHERE Id = :acc.Id];
    System.assertEquals(5, acc.AnnualRevenue);
    System.assertEquals(1, acc.NumberOfEmployees);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
    secondParent = [SELECT AnnualRevenue, NumberOfEmployees FROM Account WHERE Id = :secondParent.Id];
    System.assertEquals(null, secondParent.AnnualRevenue, 'Second parent should have been excluded from bulk update');
    System.assertEquals(null, secondParent.NumberOfEmployees, 'Second parent should have been excluded from bulk update');
  }
}
