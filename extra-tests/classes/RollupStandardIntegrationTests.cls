@IsTest
private class RollupStandardIntegrationTests {
  @TestSetup
  static void setup() {
    upsert new RollupSettings__c(IsEnabled__c = true);
    // gets nulled out at the end of the setup context
    insert new Account(Name = 'RollupStandardIntegrationTests');
  }

  @IsTest
  static void shouldConcatDistinctOnUpdateEvenIfNewItemDoesNotMatch() {
    Account acc = [SELECT Id, AccountNumber FROM Account];
    acc.AccountNumber = 'test update';
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(
      ParentId = acc.Id,
      Name = acc.AccountNumber
    );
    insert cpa;

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, Name = 'something else') };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT_DISTINCT',
        CalcItem__c = 'ContactPointAddress',
        CalcItemWhereClause__c = 'Name != \'' + acc.AccountNumber + '\''
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT AccountNumber FROM Account];
    System.assertEquals(
      null,
      updatedAcc.AccountNumber,
      'CONCAT_DISTINCT AFTER_UPDATE should clear when updated item does not match and no other items'
    );
  }

  @IsTest
  static void shouldCountDistinctOnUpdateEvenIfNewItemDoesNotMatch() {
    Account acc = [SELECT Id, Name, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 1;
    update acc;

    ContactPointAddress cpa = new ContactPointAddress(
      ParentId = acc.Id,
      Name = 'Testing CPA COUNT_DISTINCT update',
      PreferenceRank = 0
    );
    insert cpa;

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.oldRecordsMap = new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(Id = cpa.Id, PreferenceRank = 1) };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;
    Rollup.shouldRun = true;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT_DISTINCT',
        CalcItem__c = 'ContactPointAddress',
        CalcItemWhereClause__c = 'PreferenceRank > 0'
      )
    };

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    Account updatedAcc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(
      0,
      updatedAcc.AnnualRevenue,
      'COUNT_DISTINCT AFTER_UPDATE should clear when updated item does not match and no other items'
    );
  }

  @IsTest
  static void shouldNotFailForTruncatedTextFields() {
    Account acc = [SELECT Id FROM Account];
    Integer maxAccountNameLength = Account.Name.getDescribe().getLength();
    Contact con = new Contact(AccountId = acc.Id, Description = '0'.repeat(maxAccountNameLength + 1), LastName = 'Truncate', Email = 'rollup@gmail.com');
    insert con;

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'Contact',
      RollupFieldOnCalcItem__c = 'Description',
      LookupFieldOnCalcItem__c = 'AccountId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'Name',
      LookupObject__c = 'Account',
      RollupOperation__c = 'CONCAT'
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT Name FROM Account];
    System.assertEquals(maxAccountNameLength, acc.Name.length(), acc.Name);
  }

  @IsTest
  static void shouldEnqueueCMDTRecalcWhenBelowQueryLimits() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveCMDT', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixCMDT', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'PreferenceRank = ' + cpas[0].PreferenceRank
      )
    };

    Map<String, List<Rollup__mdt>> calcItemToMetadata = Rollup.getRollupMetadataByCalcItem();

    Test.startTest();
    Rollup.performBulkFullRecalc(calcItemToMetadata.get('ContactPointAddress'), Rollup.InvocationPoint.FROM_LWC.name());
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @IsTest
  static void shouldRunRollupSyncWhenFiredFromParentRecalcInvocation() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneCMDTSync', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoCMDTSync', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeCMDTSync', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourCMDTSync', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveCMDTSync', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixCMDTSync', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'PreferenceRank = ' + cpas[0].PreferenceRank + ' ||| ParentId = \'' + acc.Id + '\''
      )
    };

    Map<String, List<Rollup__mdt>> calcItemToMetadata = Rollup.getRollupMetadataByCalcItem();

    // specifically don't wrap in start/stopTest to prove it ran sync
    Rollup.performBulkFullRecalc(calcItemToMetadata.get('ContactPointAddress'), Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldCorrectlyQueryOrderByFieldForBulkRecalc() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneLast', ParentId = acc.Id, PreferenceRank = 2),
      new ContactPointAddress(Name = 'twoLast', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'LAST',
        OrderByFirstLast__c = 'PreferenceRank',
        CalcItemWhereClause__c = ' ||| ParentId = \'' + acc.Id + '\''
      )
    };

    Map<String, List<Rollup__mdt>> calcItemToMetadata = Rollup.getRollupMetadataByCalcItem();

    // specifically don't wrap in start/stopTest to prove it ran sync
    Rollup.performBulkFullRecalc(calcItemToMetadata.get('ContactPointAddress'), Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());

    acc = [SELECT Name FROM Account];
    System.assertEquals(cpas[0].Name, acc.Name, 'Last should have been selected based on order field');
  }

  @IsTest
  static void shouldCorrectlyBulkRecalcWhenParentObjectsDiffer() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneLast', ParentId = acc.Id, PreferenceRank = 2),
      new ContactPointAddress(Name = 'twoLast', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    insert new Task(Subject = 'Task rollup', WhatId = acc.Id);

     List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'LAST',
        OrderByFirstLast__c = 'PreferenceRank',
        CalcItemWhereClause__c = ' ||| ParentId = \'' + acc.Id + '\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT'
      )
    };

    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());
    acc = [SELECT Name, AccountNumber FROM Account];
    System.assertEquals(cpas[0].Name, acc.Name, 'Last should have been selected based on order field');
    System.assertEquals('Task rollup', acc.AccountNumber);
  }

  // TODO - uncomment this and implement to work on fix for https://github.com/jamessimone/apex-rollup/issues/149
  // @IsTest
  // static void shouldCorrectlyResetParentValueFromSingularRecalcWithNoChildren() {
  //   Account acc = [SELECT Id FROM Account];
  //   acc.AccountNumber = 'someString';
  //   acc.AnnualRevenue = 5;
  //   update acc;

  //   List<Rollup__mdt> metas = new List<Rollup__mdt>{
  //     new Rollup__mdt(
  //       CalcItem__c = 'ContactPointAddress',
  //       RollupFieldOnCalcItem__c = 'PreferenceRank',
  //       LookupFieldOnCalcItem__c = 'ParentId',
  //       LookupObject__c = 'Account',
  //       LookupFieldOnLookupObject__c = 'Id',
  //       RollupFieldOnLookupObject__c = 'AnnualRevenue',
  //       RollupOperation__c = 'LAST',
  //       CalcItemWhereClause__c = ' ||| ParentId = \'' + acc.Id + '\''
  //     ),
  //     new Rollup__mdt(
  //       CalcItem__c = 'Task',
  //       RollupFieldOnCalcItem__c = 'Subject',
  //       LookupFieldOnCalcItem__c = 'WhatId',
  //       LookupObject__c = 'Account',
  //       LookupFieldOnLookupObject__c = 'Id',
  //       RollupFieldOnLookupObject__c = 'AccountNumber',
  //       RollupOperation__c = 'CONCAT'
  //     )
  //   };

  //   Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());
  //   acc = [SELECT AccountNumber, AnnualRevenue FROM Account];
  //   System.assertEquals(RollupFieldInitializer.Current.getDefaultValue(Account.AccountNumber), acc.AccountNumber, 'AccountNumber should have been reset');
  //   System.assertEquals(RollupFieldInitializer.Current.getDefaultValue(Account.AnnualRevenue), acc.AnnualRevenue, 'AnnualRevenue should have been reset');
  // }

  @IsTest
  static void shouldEnqueueFullRecalculationWhenBelowQueryLimits() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'one', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'two', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'three', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'four', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'five', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'six', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM'
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
  }

  @IsTest
  static void shouldBatchForFullRecalcWhenOverLimits() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 5; // validate that the pre-existing value is cleared
    update acc;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixBatch', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup.defaultControl = new RollupControl__mdt(
      MaxLookupRowsBeforeBatching__c = 1,
      BatchChunkSize__c = 10,
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.QUEUEABLE, // validate that it still batches
      IsRollupLoggingEnabled__c = true
    );

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'Name != \'\''
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(6, acc.AnnualRevenue);
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApexWorker'].Status);
  }

  @IsTest
  static void shouldNotAddToExistingAmountForFullRecalc() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 60;
    update acc;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneExisting', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoExisting', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM'
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue);
  }

  // also an integration test for querying relationship names
  // on CalcItemWhereClause__c Rollup__mdt field
  @IsTest
  static void shouldSuccessfullyExcludeBasedOnWhereCriteriaDuringFullRecalc() {
    Account acc = [SELECT Id, AnnualRevenue, Name FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneName', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoName', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'Parent.Name != \'' + acc.Name + '\''
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    Account updatedAcc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(acc.AnnualRevenue, updatedAcc.AnnualRevenue, 'Account should not have been updated based on exclusion criteria');
  }

  @IsTest
  static void shouldCorrectlyQueryOrderByFieldForFullRecalcFirst() {
    Account acc = [SELECT Id, AnnualRevenue, Name FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneName', ParentId = acc.Id, PreferenceRank = 3),
      new ContactPointAddress(Name = 'twoName', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'Name',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'Name',
      LookupObject__c = 'Account',
      RollupOperation__c = 'FIRST',
      OrderByFirstLast__c = 'PreferenceRank'
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    Account updatedAcc = [SELECT Name FROM Account];
    System.assertEquals(cpas[1].Name, updatedAcc.Name, 'Should have taken first based on PreferenceRank');
  }

  @IsTest
  static void shouldRunSyncWhenFlaggedOnRollupLimit() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 1, Name = 'oneCpa'),
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 1, Name = 'twoCpa')
    };
    insert cpas;

    Rollup.records = cpas;
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = 'Synchronous Rollup');

    // specifically do NOT wrap in Test.startTest() / Test.stopTest() - we need to ensure this happened synchronously
    Rollup.countFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue, 'COUNT AFTER_INSERT should add when field is populated sync calc');
  }

  @IsTest
  static void shouldPartiallyDeferRollupCalculationWhenOverLimits() {
    Rollup.specificControl = new RollupControl__mdt(ShouldAbortRun__c = true);
    Account acc = [SELECT Id, OwnerId FROM Account];
    Account secondParent = new Account(Name = 'Second parent');
    insert secondParent;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'One', PreferenceRank = 1),
      new ContactPointAddress(ParentId = secondParent.Id, Name = 'Two', PreferenceRank = 1)
    };
    insert cpas;

    Rollup.defaultControl = new RollupControl__mdt(
      BatchChunkSize__c = 1,
      MaxRollupRetries__c = 1,
      MaxNumberOfQueries__c = 2,
      IsRollupLoggingEnabled__c = true
    );
    // start as synchronous rollup to allow for one deferral
    Rollup.specificControl = new RollupControl__mdt(ShouldRunAs__c = 'Synchronous Rollup');

    Rollup.shouldRun = true;
    Rollup.records = cpas;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        // use one of the full recalc operations - one SOQL per parent object will get us to defer
        // between lookup items
        RollupOperation__c = 'AVERAGE'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    // validate that queueable ran in addition to sync job
    System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'Queueable' LIMIT 1]?.Status);
    List<Account> updatedAccounts = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, updatedAccounts.size(), 'Both parent items should have been updated!');

    for (Account updatedAcc : updatedAccounts) {
      System.assertEquals(1, updatedAcc.AnnualRevenue, 'Average annual revenue should have been set for both records!');
    }
  }

  @IsTest
  static void shouldRunDirectlyFromApex() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 5),
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 10)
    };

    Rollup.records = cpas;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItem__c = 'ContactPointAddress'
      )
    };

    Test.startTest();
    Rollup.runFromApex(cpas, TriggerOperation.AFTER_INSERT);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(15, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldDeferUpdateWhenMaxParentRowsLessThanCurrentUpdateRows() {
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress cpa = new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 50, Name = 'MaxParentRows');
    insert cpa;

    Rollup.records = new List<ContactPointAddress>{ cpa };
    Rollup.shouldRun = true;
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    RollupAsyncProcessor.shouldRunAsBatch = true;
    Rollup.defaultControl = new RollupControl__mdt(MaxParentRowsUpdatedAtOnce__c = 0, BatchChunkSize__c = 1, IsRollupLoggingEnabled__c = true);

    Test.startTest();
    Rollup.sumFromApex(ContactPointAddress.PreferenceRank, ContactPointAddress.ParentId, Account.Id, Account.AnnualRevenue, Account.SObjectType).runCalc();
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(50, acc.AnnualRevenue, 'Account should have been updated since the mock is not used async');
  }

  @IsTest
  static void shouldThrowExceptionWhenTryingToOperateOnDisallowedFieldTypes() {
    Account acc = [SELECT Id FROM Account];
    Rollup.records = new List<Task>{ new Task(ActivityDate = System.today(), WhatId = acc.Id) };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;
    Rollup.shouldRun = true;

    Exception ex;
    try {
      Test.startTest();
      Rollup.maxFromApex(Task.ActivityDate, Task.WhatId, Account.Id, Account.BillingAddress, Account.SObjectType).runCalc();
      Test.stopTest();
    } catch (Exception e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
    System.assertEquals('Field: BillingAddress of type: ADDRESS specified invalid for rollup operation', ex.getMessage());
  }

  /** Invocable integration tests */

  @IsTest
  static void shouldTryToUpsertFromFlow() {
    Account acc = [SELECT Id FROM Account];

    ContactPointAddress cpa = new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'Upsert Flow Test');
    insert cpa; // aping an after-insert action in Flow

    List<ContactPointAddress> cpas = [SELECT Id, ParentId, CreatedDate, LastModifiedDate, PreferenceRank FROM ContactPointAddress];

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'UPSERT', 'SUM');
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{ null }; // sad but true - this is what flow passes for {!$Record__Prior} on upsert

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(cpas[0].PreferenceRank, updatedAcc.AnnualRevenue, 'pseudo-upsert from flow should act like insert for PreferenceRank');
  }

  @IsTest
  static void shouldPerformFullRecalcFromFlowChildren() {
    Account acc = [SELECT Id FROM Account];
    // ensure another matching item exists outside of the passed in list
    insert new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One');

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 1000, ParentId = acc.Id, Name = 'Two')
    };
    insert cpas;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(1500, updatedAcc.AnnualRevenue, 'SUM REFRESH from flow should fully recalc');
  }

  @IsTest
  static void shouldPerformFullRecalcFromFlowChildrenWithReparenting() {
    Account acc = [SELECT Id FROM Account];
    Account reparentedAccount = new Account(Name = 'Reparented Refresh', AnnualRevenue = 1000);
    insert reparentedAccount;

    insert new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One');

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = reparentedAccount.AnnualRevenue.intValue(), ParentId = reparentedAccount.Id, Name = 'Two')
    };
    insert cpas;

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(cpas, 'REFRESH', 'SUM');
    ContactPointAddress clonedCpa = cpas[0].clone(true);
    flowInputs[0].oldRecordsToRollup = new List<ContactPointAddress>{ clonedCpa };
    cpas[0].ParentId = acc.Id;
    flowInputs[0].recordsToRollup = cpas;
    update cpas;

    Test.startTest();
    Rollup.performRollup(flowInputs);
    Test.stopTest();

    acc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(1500, acc.AnnualRevenue, 'SUM REFRESH from flow should fully recalc');
    reparentedAccount = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :reparentedAccount.Id];
    System.assertEquals(0, reparentedAccount.AnnualRevenue, 'Reparenting with REFRESH should run decrement logic on old parent');
  }

  @IsTest
  static void shouldPerformFullRecalcFromFlowParent() {
    List<Account> accs = [SELECT Id, AnnualRevenue FROM Account];

    insert new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 500, ParentId = accs[0].Id, Name = 'One'),
      new ContactPointAddress(PreferenceRank = 1000, ParentId = accs[0].Id, Name = 'Two')
    };

    List<Rollup.FlowInput> flowInputs = RollupTestUtils.prepareFlowTest(accs, 'REFRESH', 'SUM');
    flowInputs[0].isRollupStartedFromParent = true;
    flowInputs[0].calcItemTypeWhenRollupStartedFromParent = 'ContactPointAddress';

    Test.startTest();
    List<Rollup.FlowOutput> flowOutputs = Rollup.performRollup(flowInputs);
    Test.stopTest();

    System.assertEquals(1, flowOutputs.size(), 'Flow outputs were not provided');
    System.assertEquals('SUCCESS', flowOutputs[0].message);
    System.assertEquals(true, flowOutputs[0].isSuccess);

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(1500, updatedAcc.AnnualRevenue, 'SUM REFRESH from flow should fully recalc');
  }

  /** Schedulable tests */
  @IsTest
  static void shouldThrowExceptionForBadQuery() {
    // it's a date field - you tell ME why this query is invalid!
    String veryBadQuery = 'SELECT MAX(ActivityDate) FROM Task';

    Exception ex;
    try {
      Rollup.schedule('Test bad query', '0 0 0 0 0', veryBadQuery, 'Account', null);
    } catch (Exception e) {
      ex = e;
    }

    System.assertNotEquals(null, ex);
  }

  @IsTest
  static void shouldScheduleSuccessfullyForGoodQuery() {
    String goodQuery = 'SELECT Id, Name FROM ContactPointAddress WHERE CreatedDate > YESTERDAY';

    String jobId = Rollup.schedule('Test good query' + System.now(), '0 0 0 * * ?', goodQuery, 'ContactPointAddress', null);

    System.assertNotEquals(null, jobId);
  }
}
