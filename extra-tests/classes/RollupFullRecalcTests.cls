@IsTest
private class RollupFullRecalcTests {
  @TestSetup
  static void setup() {
    Account acc = new Account(Name = RollupFullRecalcTests.class.getName());
    insert acc;

    upsert new RollupSettings__c(IsEnabled__c = true);
  }

  @IsTest
  static void correctlyOrdersGrandparentRollupQueryString() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true, MaxLookupRowsBeforeBatching__c = 0);
    insert new Contact(LastName = 'grandparent rollup query string');

    Rollup.performBulkFullRecalc(
      new List<Rollup__mdt>{
        new Rollup__mdt(
          CalcItem__c = 'Contact',
          GrandparentRelationshipFieldPath__c = 'ReportsTo.Account.Name',
          LookupFieldOnCalcItem__c = 'ReportsToId',
          LookupFieldOnLookupObject__c = 'Id',
          LookupObject__c = 'Account',
          RollupFieldOnCalcItem__c = 'FirstName',
          RollupFieldOnLookupObject__c = 'Name',
          RollupOperation__c = 'CONCAT'
        )
      },
      Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name()
    );

    System.assertEquals(1, Rollup.CACHED_FULL_RECALCS.size());
    List<String> queryParts = Rollup.CACHED_FULL_RECALCS.get(0).start(null).getQuery().split('\n');
    System.assertEquals('ORDER BY ReportsTo.Account.Id,ReportsToId,Id', queryParts.get(queryParts.size() - 1));
  }

  @IsTest
  static void shouldSortParentResetProcessorsToBeginning() {
    RollupAsyncProcessor actualProcessor = RollupAsyncProcessor.getProcessor(
      new Rollup.FilterResults(),
      Contact.Id,
      Contact.AccountId,
      Account.Id,
      Account.Name,
      Account.SObjectType,
      Contact.SObjectType,
      Rollup.Op.SUM,
      Rollup.InvocationPoint.FROM_APEX,
      null,
      null
    );
    RollupParentResetProcessor resetProcessor = new RollupParentResetProcessor(
      new List<Rollup__mdt>(),
      null,
      '',
      new Set<String>(),
      Rollup.InvocationPoint.FROM_APEX
    );
    List<RollupAsyncProcessor> processors = new List<RollupAsyncProcessor>{
      resetProcessor,
      actualProcessor,
      actualProcessor,
      resetProcessor,
      actualProcessor,
      resetProcessor
    };
    processors.sort();

    System.assertEquals(true, processors[0] instanceof RollupParentResetProcessor, processors[0]);
    System.assertEquals(true, processors[1] instanceof RollupParentResetProcessor, processors[0]);
    System.assertEquals(true, processors[2] instanceof RollupParentResetProcessor, processors[0]);
  }

  @IsTest
  static void shouldPerformBulkFullRecalcWithHierarchy() {
    // also validates that RollupRelationshipFieldFinder aborts early if it's called
    // for a top-level parent
    Rollup.defaultControl = new RollupControl__mdt(ShouldAbortRun__c = true, IsRollupLoggingEnabled__c = true);

    Account acc = [SELECT Id FROM Account];
    Account childAccount = new Account(Name = 'Hierarchy child', ParentId = acc.Id, AnnualRevenue = 5);
    insert childAccount;

    Rollup.shouldRefreshCachedControl = true;
    Rollup.onlyUseMockMetadata = true;
    List<Rollup__mdt> metadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Account',
        LookupObject__c = 'Account',
        RollupToUltimateParent__c = true,
        LookupFieldOnCalcItem__c = 'ParentId',
        UltimateParentLookup__c = 'ParentId',
        RollupOperation__c = 'SUM',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupFieldOnCalcItem__c = 'AnnualRevenue',
        LookupFieldOnLookupObject__c = 'Id'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metadata, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    acc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(childAccount.AnnualRevenue, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldPerformFullRecalcWithGrandparentHierarchyApex() {
    Rollup.onlyUseMockMetadata = true; // necessary for namespaced package generation
    Account acc = [SELECT Id FROM Account];
    Account childAccount = new Account(Name = 'Hierarchy child', ParentId = acc.Id);
    insert childAccount;
    ParentApplication__c parentApp = new ParentApplication__c(Account__c = childAccount.Id, Name = 'Link to child account');
    ParentApplication__c secondParentApp = new ParentApplication__c(Account__c = acc.Id, Name = 'Linked directly to parent account');
    insert new List<ParentApplication__c>{ parentApp, secondParentApp };

    // ensure that both a top-level child item linked only to the ultimate parent and one linked to the hierarchy child is included
    List<Application__c> apps = new List<Application__c>{
      new Application__c(Engagement_Score__c = 1000, ParentApplication__c = parentApp.Id, Name = 'Linked to Child Parent App'),
      new Application__c(Engagement_Score__c = 1000, ParentApplication__c = secondParentApp.Id, Name = 'Linked to Direct Parent App')
    };
    insert apps;

    List<Rollup__mdt> metadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = Application__c.SObjectType.toString(),
        LookupObject__c = 'Account',
        RollupToUltimateParent__c = true,
        LookupFieldOnCalcItem__c = Application__c.ParentApplication__c.toString(),
        UltimateParentLookup__c = 'ParentId',
        RollupOperation__c = 'SUM',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupFieldOnCalcItem__c = Application__c.Engagement_Score__c.toString(),
        LookupFieldOnLookupObject__c = 'Id',
        GrandparentRelationshipFieldPath__c = RollupTestUtils.getRelationshipPath(
          new List<Schema.SObjectField>{ Application__c.ParentApplication__c, ParentApplication__c.Account__c, Account.AnnualRevenue }
        )
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metadata, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    Account updatedAcc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(2000, updatedAcc.AnnualRevenue, 'Apex grandparent rollup should fully recalc');
  }

  @IsTest
  static void supportsOneToManyFullRecalcInMiddleOfChain() {
    Rollup.onlyUseMockMetadata = true; // necessary for namespaced package generation
    Account acc = [SELECT Id FROM Account];
    Individual indy = new Individual(LastName = 'Indy');
    insert indy;
    Contact con = new Contact(LastName = 'One To Many Child', AccountId = acc.Id, IndividualId = indy.Id);
    insert con;

    ParentApplication__c parentApp = new ParentApplication__c(Account__c = acc.Id, Name = 'One');
    ParentApplication__c secondParentApp = new ParentApplication__c(Account__c = acc.Id, Name = 'Two');
    insert new List<ParentApplication__c>{ parentApp, secondParentApp };

    List<Application__c> apps = new List<Application__c>{
      new Application__c(Engagement_Score__c = 1000, ParentApplication__c = parentApp.Id, Name = 'App One'),
      new Application__c(Engagement_Score__c = 1000, ParentApplication__c = secondParentApp.Id, Name = 'App Two')
    };
    insert apps;

    List<Rollup__mdt> metadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = Application__c.SObjectType.toString(),
        LookupObject__c = 'Individual',
        LookupFieldOnCalcItem__c = Application__c.ParentApplication__c.toString(),
        RollupOperation__c = 'SUM',
        RollupFieldOnLookupObject__c = 'ConsumerCreditScore',
        RollupFieldOnCalcItem__c = Application__c.Engagement_Score__c.toString(),
        LookupFieldOnLookupObject__c = 'Id',
        GrandparentRelationshipFieldPath__c = String.valueOf(Application__c.ParentApplication__c).replace('__r', '__c') +
          '.' +
          String.valueOf(ParentApplication__c.Account__c).replace('__c', '__r') +
          '.Contacts.Individual.ConsumerCreditScore',
        OneToManyGrandparentFields__c = 'Contact.AccountId'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metadata, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    Individual updatedIndy = [SELECT Id, ConsumerCreditScore FROM Individual WHERE Id = :indy.Id];
    System.assertEquals(2000, updatedIndy.ConsumerCreditScore, 'Apex grandparent rollup should fully recalc with one to many field path');
  }

  @IsTest
  static void supportsOneToManyAtBeginningOfChain() {
    Rollup.onlyUseMockMetadata = true;
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    acc.AnnualRevenue = 67;
    update acc;

    Individual indy = new Individual(LastName = 'Indy');
    insert indy;
    Contact con = new Contact(LastName = 'One To Many Child', AccountId = acc.Id, IndividualId = indy.Id);
    insert con;

    List<Rollup__mdt> metadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Account',
        LookupObject__c = 'Individual',
        LookupFieldOnCalcItem__c = 'Id',
        RollupOperation__c = 'SUM',
        RollupFieldOnLookupObject__c = 'ConsumerCreditScore',
        RollupFieldOnCalcItem__c = 'AnnualRevenue',
        LookupFieldOnLookupObject__c = 'Id',
        GrandparentRelationshipFieldPath__c = 'Contacts.Individual.ConsumerCreditScore',
        OneToManyGrandparentFields__c = 'Contact.AccountId'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metadata, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    Individual updatedIndy = [SELECT Id, ConsumerCreditScore FROM Individual WHERE Id = :indy.Id];
    System.assertEquals(acc.AnnualRevenue, updatedIndy.ConsumerCreditScore, 'Apex grandparent rollup should fully recalc with one to many field path');
  }

  @IsTest
  static void doesNotUpdateParentRecordsWhereRollupValueHasNotChangedInFullRecalc() {
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;

    Account acc = [SELECT Id FROM Account];
    Account secondParent = new Account(Name = 'Second', NumberOfEmployees = 1);
    insert secondParent;
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One'),
      // ensure that the count of children records associated with the second parent DOES match
      // the second parent's existing NumberOfEmployees; here we are looking to ensure only the parent records needing an update are saved
      new ContactPointAddress(ParentId = secondParent.Id, Name = 'Two')
    };
    insert cpas;

    List<Rollup__mdt> metadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupOperation__c = 'SUM',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnLookupObject__c = 'Id',
        CalcItemWhereClause__c = 'Name != \'Two\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupOperation__c = 'COUNT',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupFieldOnCalcItem__c = 'Id',
        LookupFieldOnLookupObject__c = 'Id',
        CalcItemWhereClause__c = 'Name != \'One\''
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metadata, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    Map<Id, SObject> updatedRecordMap = new Map<Id, SObject>(mock.Records);
    System.assertEquals(1, updatedRecordMap.size());
    System.assertEquals(true, updatedRecordMap.containsKey(acc.Id));
  }

  @IsTest
  static void updatesParentRecordsWhenAtLeastOneCmdtRecordDoesNotHaveWhereClause() {
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;

    Account acc = [SELECT Id FROM Account];
    Account secondParent = new Account(Name = 'Two', Description = 'Two');
    insert secondParent;
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One'),
      new ContactPointAddress(ParentId = secondParent.Id, Name = secondParent.Name)
    };
    insert cpas;

    List<Rollup__mdt> metadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupOperation__c = 'SUM',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnLookupObject__c = 'Id',
        CalcItemWhereClause__c = 'Name != \'Two\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupOperation__c = 'COUNT',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupFieldOnCalcItem__c = 'Id',
        LookupFieldOnLookupObject__c = 'Id',
        CalcItemWhereClause__c = 'Name != \'Two\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupOperation__c = 'CONCAT',
        RollupFieldOnLookupObject__c = 'Description',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnLookupObject__c = 'Id'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metadata, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    Map<Id, SObject> updatedRecordMap = new Map<Id, SObject>(mock.Records);
    System.assertEquals(true, updatedRecordMap.containsKey(acc.Id));
    System.assertNotEquals(true, updatedRecordMap.containsKey(secondParent.Id));
    System.assertEquals(cpas[0].Name, updatedRecordMap.get(acc.Id).get('Description'));
  }

  @IsTest
  static void preventsParentRecordResetsWhenControlIsFlagged() {
    Rollup.defaultControl = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 2, ShouldSkipResettingParentFields__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = 75;
    acc.NumberOfEmployees = 15;
    update acc;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{ new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One') };
    insert cpas;

    List<Rollup__mdt> metadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupOperation__c = 'SUM',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnLookupObject__c = 'Id',
        CalcItemWhereClause__c = 'Name != \'One\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupOperation__c = 'COUNT',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupFieldOnCalcItem__c = 'Id',
        LookupFieldOnLookupObject__c = 'Id',
        CalcItemWhereClause__c = 'Name != \'One\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupOperation__c = 'CONCAT',
        RollupFieldOnLookupObject__c = 'Description',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnLookupObject__c = 'Id'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metadata, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    Account updatedAccount = [SELECT AnnualRevenue, NumberOfEmployees FROM Account WHERE Id = :acc.Id];
    System.assertEquals(acc, updatedAccount);
  }

  @IsTest
  static void doesNotUpdateParentRecordsWithoutUpdatesWhenRecordsExcludedByEvaluator() {
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;

    Account acc = [SELECT Id FROM Account];
    Account secondParent = new Account(Name = 'Second');
    insert secondParent;
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(PreferenceRank = 500, ParentId = acc.Id, Name = 'One'),
      new ContactPointAddress(ParentId = secondParent.Id, Name = 'Two')
    };
    insert cpas;

    List<Rollup__mdt> metadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupOperation__c = 'SUM',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnLookupObject__c = 'Id'
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'ParentId',
        RollupOperation__c = 'COUNT',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupFieldOnCalcItem__c = 'Id',
        LookupFieldOnLookupObject__c = 'Id',
        CalcItemWhereClause__c = 'ParentId != \'' + secondParent.Id + '\''
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metadata, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    Map<Id, SObject> updatedRecordMap = new Map<Id, SObject>(mock.Records);
    System.assertEquals(1, updatedRecordMap.size());
    System.assertEquals(true, updatedRecordMap.containsKey(acc.Id));
    acc = (Account) mock.Records[0];
    System.assertEquals(500, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldProperlyBulkifyApexFullRecalcs() {
    // cheating, but we'll use REFRESH_ rollup operations to reproduce this issue (REFRESH is typically only available in Flow)
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<Event> events = new List<Event>{
      new Event(WhatId = acc.Id, Subject = 'One', ActivityDatetime = System.now(), DurationInMinutes = 60),
      new Event(WhatId = acc.Id, Subject = 'Two', ActivityDatetime = System.now(), DurationInMinutes = 60)
    };
    insert events;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.shouldRun = true;
    Rollup.records = events;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'REFRESH_CONCAT'
      ),
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'Id',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'REFRESH_COUNT',
        CalcItemWhereClause__c = 'WhatId = \'' + acc.Id + '\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'DurationInMinutes',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupOperation__c = 'REFRESH_SUM'
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_DELETE;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(0, mock.Records.size(), 'No updates should have been made for non-merge delete');
  }

  @IsTest
  static void shouldAllowGrandparentRollupsFromParent() {
    // also an integration test for having an ORDER BY statement
    // in RollupFullBatchRecalculator
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<Event> events = new List<Event>{
      new Event(WhatId = acc.Id, Subject = 'One', ActivityDatetime = System.now(), DurationInMinutes = 60),
      new Event(WhatId = acc.Id, Subject = 'Two', ActivityDatetime = System.now(), DurationInMinutes = 60)
    };
    insert events;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.shouldRun = true;
    Rollup.records = [SELECT Id, AboutMe FROM User WHERE Id = :acc.OwnerId];
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'User',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AboutMe',
        RollupOperation__c = 'CONCAT',
        GrandparentRelationshipFieldPath__c = 'What.Owner.AboutMe',
        IsRollupStartedFromParent__c = true,
        CalcItemWhereClause__c = 'What.Type = \'Account\''
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Grandparent record should have been found!');
    User updatedUser = (User) mock.Records[0];
    System.assertEquals(events[0].Subject + ', ' + events[1].Subject, updatedUser.AboutMe, 'Grandparent rollup should have worked!');
  }

  @IsTest
  static void shouldMapChildrenWithDifferentGrandparentWhereClauses() {
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<Event> events = new List<Event>{
      new Event(WhatId = acc.Id, Subject = 'Two', ActivityDatetime = System.now(), DurationInMinutes = 30),
      new Event(WhatId = acc.Id, Subject = 'One', ActivityDatetime = System.now(), DurationInMinutes = 60)
    };
    insert events;

    Rollup.defaultControl = Rollup.getDefaultControl();
    Rollup.defaultControl.ShouldSkipResettingParentFields__c = true;
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'User',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AboutMe',
        RollupOperation__c = 'CONCAT',
        GrandparentRelationshipFieldPath__c = 'What.Owner.AboutMe',
        CalcItemWhereClause__c = 'DurationInMinutes <= 30'
      ),
      new Rollup__mdt(
        CalcItem__c = 'Event',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'User',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'CompanyName',
        RollupOperation__c = 'CONCAT',
        GrandparentRelationshipFieldPath__c = 'What.Owner.CompanyName',
        CalcItemWhereClause__c = 'DurationInMinutes > 30'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(Rollup.rollupMetadata, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    User updatedUser = [SELECT AboutMe, CompanyName FROM User WHERE Id = :acc.OwnerId];
    System.assertEquals(events[0].Subject, updatedUser.AboutMe);
    System.assertEquals(events[1].Subject, updatedUser.CompanyName);
  }

  @IsTest
  static void shouldAllowGrandparentRollupFromParentWithPolymorphicFields() {
    // technically shouldAllowGrandparentRollupsFromParent also tests polymorphic fields
    // this test does that in conjunction with a more complicated where clause
    Account acc = [SELECT Id, OwnerId FROM Account];
    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, Name = 'One'),
      new ContactPointAddress(ParentId = acc.Id, Name = 'Two')
    };
    insert cpas;

    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;
    Rollup.shouldRun = true;
    Rollup.records = [SELECT Id, AboutMe FROM User WHERE Id = :acc.OwnerId];
    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'User',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AboutMe',
        RollupOperation__c = 'CONCAT',
        GrandparentRelationshipFieldPath__c = 'Parent.Owner.AboutMe',
        IsRollupStartedFromParent__c = true,
        CalcItemWhereClause__c = 'ParentId = \'' + acc.Id + '\' OR Parent.Type = \'Account\''
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_INSERT;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Grandparent record should have been found!');
    User updatedUser = (User) mock.Records[0];
    System.assertEquals(cpas[0].Name + ', ' + cpas[1].Name, updatedUser.AboutMe, 'Grandparent rollup should have worked!');
  }

  /** Parent-initiated rollups */
  @IsTest
  static void shouldAllowRollupToBeInitiatedFromTheParent() {
    Account acc = [SELECT Id, AnnualRevenue FROM Account];
    Asset asset = new Asset(AccountId = acc.Id, Name = 'Rollup initiated from parent', Quantity = 500);
    insert asset;

    Rollup.rollupMetadata = new List<Rollup__mdt>{
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Quantity',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'COUNT',
        CalcItem__c = 'Asset',
        IsRollupStartedFromParent__c = true
      ),
      new Rollup__mdt(
        RollupFieldOnCalcItem__c = 'Name',
        LookupObject__c = 'Account',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT',
        CalcItem__c = 'Asset',
        IsRollupStartedFromParent__c = true
      )
    };
    Rollup.apexContext = TriggerOperation.AFTER_UPDATE;

    Rollup.records = new List<Account>{ acc };
    Rollup.oldRecordsMap = new Map<Id, Account>{ acc.Id => new Account(Id = acc.Id, AnnualRevenue = 0) };
    Rollup.shouldRun = true;
    RollupTestUtils.DMLMock mock = new RollupTestUtils.DMLMock();
    Rollup.DML = mock;

    Test.startTest();
    Rollup.runFromTrigger();
    Test.stopTest();

    System.assertEquals(1, mock.Records.size(), 'Records should have been updated based on parent metadata AFTER_UPDATE');
    Account updatedAcc = (Account) mock.Records[0];
    System.assertNotEquals(acc.AnnualRevenue, updatedAcc.AnnualRevenue, 'Account should now have been updated');
    System.assertEquals(1, updatedAcc.AnnualRevenue, 'Account should have been updated with asset count');
    System.assertEquals(asset.Name, updatedAcc.Name);
  }

  @IsTest
  static void shouldNotFailForTruncatedTextFields() {
    Account acc = [SELECT Id FROM Account];
    Integer maxAccountNameLength = Account.Name.getDescribe().getLength();
    Contact con = new Contact(AccountId = acc.Id, Description = '0'.repeat(maxAccountNameLength + 1), LastName = 'Truncate');
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
    Rollup.performBulkFullRecalc(calcItemToMetadata.get('ContactPointAddress'), Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
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
      Rollup.appendOrderByMetadata(
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'Name',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'Name',
          RollupOperation__c = 'LAST',
          CalcItemWhereClause__c = ' ||| ParentId = \'' + acc.Id + '\''
        ),
        new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = 'PreferenceRank') }
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
      Rollup.appendOrderByMetadata(
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'Name',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'Name',
          RollupOperation__c = 'LAST',
          CalcItemWhereClause__c = ' ||| ParentId = \'' + acc.Id + '\''
        ),
        new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = 'PreferenceRank') }
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

    // no start/stopTest since singular parent recalc entry point _should_ run sync
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());
    acc = [SELECT Name, AccountNumber FROM Account];
    System.assertEquals(cpas[0].Name, acc.Name, 'Last should have been selected based on order field');
    System.assertEquals('Task rollup', acc.AccountNumber);
  }

  @IsTest
  static void shouldCorrectlyHandleNotLikeInWhereClause() {
    Account acc = [SELECT Id FROM Account];

    insert new Task(Subject = 'Task rollup', WhatId = acc.Id);

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT',
        CalcItemWhereClause__c = '(NOT Subject LIKE \'Email\') ||| WhatId = \'' + acc.Id + '\''
      )
    };

    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());
    acc = [SELECT AccountNumber FROM Account];
    System.assertEquals('Task rollup', acc.AccountNumber);
  }

  @IsTest
  static void shouldEnqueueFullRecalculationWhenBelowQueryLimits() {
    Account acc = [SELECT Id FROM Account];
    Account secondAccount = new Account(Name = 'Second');
    insert secondAccount;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'one', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'two', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'three', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'four', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'five', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'six', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'secondAccount', ParentId = secondAccount.Id, PreferenceRank = 1)
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

    List<Account> accounts = [SELECT Id, AnnualRevenue FROM Account];
    System.assertEquals(2, accounts.size());
    for (Account account : accounts) {
      System.assertEquals(account.Id == acc.Id ? 6 : 1, account.AnnualRevenue);
    }
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
      // prove that it works with multiple chunks
      BatchChunkSize__c = 2,
      MaxLookupRowsBeforeBatching__c = 1,
      // validate that it still batches
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Queueable,
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
    System.assertEquals(
      'Completed',
      [
        SELECT Status
        FROM AsyncApexJob
        WHERE JobType = 'Queueable' AND ApexClass.Name = :getNamespaceSafeClassName(RollupFullBatchRecalculator.class)
        LIMIT 1
      ]
      ?.Status
    );
  }

  @IsTest
  static void shouldUseSmallerBatchSizeWhenSpecificRollupControlLowerThanOrgDefaults() {
    Account acc = [SELECT Id FROM Account];
    Account secondAccount = new Account(Name = 'Second');
    insert secondAccount;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixBatch', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'secondAccount', ParentId = secondAccount.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup.defaultControl = new RollupControl__mdt(
      MaxLookupRowsBeforeBatching__c = 1,
      // validate that it still batches
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Queueable,
      IsRollupLoggingEnabled__c = true
    );
    Rollup.specificControl = new RollupControl__mdt(BatchChunkSize__c = 1);

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

    List<AsyncApexJob> jobs = [
      SELECT Status
      FROM AsyncApexJob
      WHERE JobType = 'Queueable' AND ApexClass.Name = :getNamespaceSafeClassName(RollupFullBatchRecalculator.class)
    ];
    System.assertEquals(false, jobs.isEmpty());
    for (AsyncApexJob job : jobs) {
      System.assertEquals('Completed', job.Status);
    }
  }

  @IsTest
  static void shouldNotBatchForFullRecalcWhenWhereClausePlacesItemsUnderneathThreshold() {
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixQueue', ParentId = acc.Id, PreferenceRank = 2)
    };
    insert cpas;

    Rollup.defaultControl = new RollupControl__mdt(
      MaxLookupRowsBeforeBatching__c = 2, // this is the important part; that only the qualified cpa ends up counting
      MaxNumberOfQueries__c = 5,
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous,
      IsRollupLoggingEnabled__c = true,
      MaxParentRowsUpdatedAtOnce__c = 2,
      MaxRollupRetries__c = 1
    );

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'PreferenceRank = 2'
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue);
    System.assertEquals(0, [SELECT COUNT() FROM AsyncApexJob WHERE JobType != 'Queueable']);
  }

  @IsTest
  static void doesNotClearParentFieldsWhenFullRecalcIsDeferred() {
    Account acc = [SELECT Id FROM Account]; // 1 query
    acc.AnnualRevenue = acc.NumberOfEmployees = 5;
    update acc;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixQueue', ParentId = acc.Id, PreferenceRank = 2)
    };
    insert cpas;

    Rollup.defaultControl = new RollupControl__mdt(
      MaxLookupRowsBeforeBatching__c = 50,
      MaxNumberOfQueries__c = 2, // set to explicitly be too low for rollup to proceed
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous,
      IsRollupLoggingEnabled__c = true,
      MaxParentRowsUpdatedAtOnce__c = 10,
      MaxRollupRetries__c = -1 // don't actually allow the deferral
    );
    // rollups are processed in reverse order
    Rollup__mdt countRollup = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'NumberOfEmployees',
      LookupObject__c = 'Account',
      RollupOperation__c = 'COUNT_DISTINCT',
      CalcItemWhereClause__c = 'PreferenceRank = 2'
    );
    Rollup__mdt sumRollup = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'PreferenceRank = 2'
    );

    Test.startTest();
    Rollup.performBulkFullRecalc(new List<Rollup__mdt>{ sumRollup, countRollup }, Rollup.InvocationPoint.FROM_APEX.name());
    Test.stopTest();

    Account updatedAccount = [SELECT AnnualRevenue, NumberOfEmployees FROM Account];
    System.assertEquals(acc, updatedAccount, 'Fields should not have been reset due to impossible deferral');
  }

  @IsTest
  static void updatesSyncWhenDeferredRollupIsInPlay() {
    Account acc = [SELECT Id FROM Account];
    acc.AnnualRevenue = acc.NumberOfEmployees = 5;
    update acc;

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'twoQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fourQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'fiveQueue', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'sixQueue', ParentId = acc.Id, PreferenceRank = 2)
    };
    insert cpas;

    Rollup.defaultControl = new RollupControl__mdt(
      MaxLookupRowsBeforeBatching__c = 50,
      MaxNumberOfQueries__c = 2, // has to be exactly the number that allows the first rollup but not the second
      ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous,
      IsRollupLoggingEnabled__c = true,
      MaxParentRowsUpdatedAtOnce__c = 10,
      MaxRollupRetries__c = -1 // don't actually allow the deferral
    );
    // rollups are processed in reverse order
    Rollup__mdt countRollup = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'NumberOfEmployees',
      LookupObject__c = 'Account',
      RollupOperation__c = 'COUNT_DISTINCT',
      CalcItemWhereClause__c = 'PreferenceRank = 2'
    );
    Rollup__mdt sumRollup = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'PreferenceRank = 2'
    );

    // RollupSObjectUpdater respects being over rollup limits
    // so we specifically do NOT wrap in start/stopTest because we need to prove the updates happen sync
    Rollup.performBulkFullRecalc(new List<Rollup__mdt>{ sumRollup, countRollup }, Rollup.InvocationPoint.FROM_APEX.name());

    acc = [SELECT AnnualRevenue, NumberOfEmployees FROM Account];
    System.assertEquals(5, acc.NumberOfEmployees, 'NumberOfEmployees should not have been calculated properly due to being deferred');
    System.assertEquals(5, acc.AnnualRevenue, 'AnnualRevenue should not have been calculated properly due to being deferred');
  }

  @IsTest
  static void shouldAllowForMutuallyExclusiveWhereClausesOnBulkFullRecalc() {
    Account acc = [SELECT Id, Name FROM Account];

    Task appliesToFirst = new Task(Subject = 'Task for first CMDT', WhatId = acc.Id);
    Task appliesToSecond = new Task(Subject = 'Task for second CMDT', WhatId = acc.Id);
    insert new List<Task>{ appliesToFirst, appliesToSecond };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AccountNumber',
        RollupOperation__c = 'CONCAT',
        CalcItemWhereClause__c = 'Subject = \'' + appliesToFirst.Subject + '\' ||| WhatId = \'' + acc.Id + '\''
      ),
      new Rollup__mdt(
        CalcItem__c = 'Task',
        RollupFieldOnCalcItem__c = 'Subject',
        LookupFieldOnCalcItem__c = 'WhatId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        RollupOperation__c = 'CONCAT_DISTINCT',
        CalcItemWhereClause__c = 'Subject = \'' + appliesToSecond.Subject + '\''
      )
    };

    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());

    acc = [SELECT AccountNumber, Name FROM Account WHERE Id = :acc.Id];

    System.assertEquals(appliesToFirst.Subject, acc.AccountNumber);
    System.assertEquals(appliesToSecond.Subject, acc.Name);
  }

  @IsTest
  static void grandparentRollupsCanUseSingularParentRecalcButton() {
    Rollup.onlyUseMockMetadata = true; // necessary for namespaced package generation
    RollupGrandparent__c grandparent = new RollupGrandparent__c();
    insert grandparent;

    RollupParent__c parent = new RollupParent__c(Name = 'Parent', RollupGrandparent__c = grandparent.Id);
    insert parent;

    insert new List<RollupChild__c>{
      new RollupChild__c(RollupParent__c = parent.Id, NumberField__c = 1),
      new RollupChild__c(RollupParent__c = parent.Id, NumberField__c = 1),
      new RollupChild__c(RollupParent__c = parent.Id, NumberField__c = 1)
    };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = RollupChild__c.SObjectType.toString(),
        RollupFieldOnCalcItem__c = RollupChild__c.NumberField__c.toString(),
        LookupFieldOnCalcItem__c = RollupChild__c.RollupParent__c.toString(),
        LookupObject__c = RollupGrandparent__c.SObjectType.toString(),
        LookupFieldOnLookupObject__c = RollupGrandparent__c.Id.toString(),
        RollupFieldOnLookupObject__c = RollupGrandparent__c.AmountFromChildren__c.toString(),
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = ' ||| ' +
          RollupTestUtils.getRelationshipPath(
            new List<Schema.SObjectField>{ RollupChild__c.RollupParent__c, RollupParent__c.RollupGrandparent__c, RollupGrandparent__c.Id }
          ) +
          ' = \'' +
          grandparent.Id +
          '\'',
        GrandparentRelationshipFieldPath__c = RollupTestUtils.getRelationshipPath(
          new List<Schema.SObjectField>{ RollupChild__c.RollupParent__c, RollupParent__c.RollupGrandparent__c, RollupGrandparent__c.AmountFromChildren__c }
        )
      )
    };

    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_SINGULAR_PARENT_RECALC_LWC.name());

    grandparent = [SELECT AmountFromChildren__c FROM RollupGrandparent__c WHERE Id = :grandparent.Id];
    System.assertEquals(3, grandparent.AmountFromChildren__c);
  }

  @IsTest
  static void shouldNotBlowUpOnMassiveQuery() {
    Integer maxLength = ContactPointAddress.PreferenceRank.getDescribe().getDigits();
    String endOfWhereClause = '2'.repeat(maxLength);
    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = ('PreferenceRank = ' + endOfWhereClause + ' AND ').repeat(200).removeEnd(' AND ')
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    System.assert(true, 'Should make it here without exception being thrown');
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

  @IsTest
  static void usesDefaultValueForFullRecalcEvenWithoutMatchingItems() {
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress cpa = new ContactPointAddress(Name = 'One', ParentId = acc.Id, PreferenceRank = 1);
    Rollup.defaultControl = new RollupControl__mdt(
      IsRollupLoggingEnabled__c = true,
      MaxLookupRowsBeforeBatching__c = 2,
      ShouldSkipResettingParentFields__c = true
    );
    insert cpa;
    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM',
      FullRecalculationDefaultNumberValue__c = 0,
      CalcItemWhereClause__c = 'Name != \'' + cpa.Name + '\''
    );
    Rollup__mdt secondMeta = new Rollup__mdt(
      CalcItem__c = 'ContactPointAddress',
      RollupFieldOnCalcItem__c = 'PreferenceRank',
      LookupFieldOnCalcItem__c = 'ParentId',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'NumberOfEmployees',
      LookupObject__c = 'Account',
      RollupOperation__c = 'SUM'
    );

    Test.startTest();
    Rollup.performBulkFullRecalc(new List<Rollup__mdt>{ meta, secondMeta }, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    Account updatedAccount = [SELECT AnnualRevenue FROM Account];
    Assert.areEqual(meta.FullRecalculationDefaultNumberValue__c, updatedAccount.AnnualRevenue);
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
    System.assertEquals(null, updatedAcc.AnnualRevenue, 'Account should not have been updated based on exclusion criteria');
  }

  @IsTest
  static void shouldCorrectlyQueryOrderByFieldForFullRecalcFirst() {
    Account acc = [SELECT Id, AnnualRevenue, Name FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneName', ParentId = acc.Id, PreferenceRank = 3),
      new ContactPointAddress(Name = 'twoName', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup__mdt meta = Rollup.appendOrderByMetadata(
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'Name',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Name',
        LookupObject__c = 'Account',
        RollupOperation__c = 'FIRST'
      ),
      new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = 'PreferenceRank') }
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    Account updatedAcc = [SELECT Name FROM Account];
    System.assertEquals(cpas[1].Name, updatedAcc.Name, 'Should have taken first based on PreferenceRank');
  }

  @IsTest
  static void resetsDatesForFirstProperly() {
    Account acc = [SELECT Id, AnnualRevenue, Name FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'one', ParentId = acc.Id, PreferenceRank = 3, ActiveFromDate = System.today()),
      new ContactPointAddress(Name = 'two', ParentId = acc.Id, PreferenceRank = 1)
    };
    insert cpas;

    Rollup__mdt meta = Rollup.appendOrderByMetadata(
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'ActiveFromDate',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Description',
        LookupObject__c = 'Account',
        RollupOperation__c = 'FIRST',
        CalcItemWhereClause__c = 'ActiveFromDate != TODAY'
      ),
      new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = 'PreferenceRank') }
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    Account updatedAcc = [SELECT Description FROM Account];
    System.assertEquals(null, updatedAcc.Description, 'Should have taken first based on PreferenceRank');
  }

  @IsTest
  static void shouldRetainFullRecalcValuesForMutuallyExclusiveRollupsToSameField() {
    Account acc = [SELECT Id, AnnualRevenue, Name FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(Name = 'oneName', ParentId = acc.Id, PreferenceRank = 3),
      new ContactPointAddress(Name = 'twoName', ParentId = acc.Id, PreferenceRank = 1),
      new ContactPointAddress(Name = 'threeName', ParentId = acc.Id, PreferenceRank = 2)
    };
    insert cpas;

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        LookupObject__c = 'Account',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'PreferenceRank = ' + cpas[0].PreferenceRank
      ),
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        LookupObject__c = 'Account',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'Name != \'' + cpas[0].Name + '\''
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(6, acc.AnnualRevenue, 'Full child amount should be included');
  }

  @IsTest
  static void shouldCorrectlyResetParentValueFromSingularRecalcWithNoChildren() {
    Account acc = [SELECT Id FROM Account];
    acc.AccountNumber = 'someString';
    acc.AnnualRevenue = 5;
    update acc;
    Account accDoesNotGetReset = new Account(Name = 'Should Not Get Reset Annual Revenue', AnnualRevenue = 4);
    insert accDoesNotGetReset;

    insert new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 0, Name = 'Should not match');

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'LAST',
        CalcItemWhereClause__c = 'PreferenceRank > 0 ||| ParentId = \'' + acc.Id + '\''
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
    acc = [SELECT AccountNumber, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(null, acc.AnnualRevenue, 'AnnualRevenue should have been reset');
    // seems like some standard fields default to null when you save an empty string to them, even if they have no default value 🙄
    System.assertEquals(null, acc.AccountNumber, 'AccountNumber should have been reset');
    accDoesNotGetReset = [SELECT AnnualRevenue FROM Account WHERE Id = :accDoesNotGetReset.Id];
    System.assertNotEquals(null, accDoesNotGetReset.AnnualRevenue);
  }

  @IsTest
  static void shouldResetParentValuesWithoutMatchingChildrenFromBulkRouteUnderQueryLimitSync() {
    Account acc = [SELECT Id FROM Account];
    acc.AccountNumber = 'someString';
    acc.AnnualRevenue = 5;
    update acc;

    Account secondParentWithValues = new Account(Name = 'Two', AnnualRevenue = 5);
    Account thirdParentWithValues = new Account(Name = 'Three', AccountNumber = '1234');
    insert new List<Account>{ secondParentWithValues, thirdParentWithValues };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'LAST',
        CalcItemWhereClause__c = 'PreferenceRank > 0'
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

    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());

    List<Account> accounts = [SELECT AccountNumber, AnnualRevenue, Name FROM Account];
    for (Account updatedAcc : accounts) {
      System.assertEquals(null, updatedAcc.AnnualRevenue, 'AnnualRevenue should have been reset: ' + updatedAcc);
      System.assertEquals(null, updatedAcc.AccountNumber, 'AccountNumber should have been reset: ' + updatedAcc);
    }
  }

  @IsTest
  static void shouldResetParentValueWithoutMatchingChildrenNotUsingId() {
    Account acc = [SELECT Id FROM Account];
    acc.AccountNumber = 'someString';
    acc.AnnualRevenue = 5;
    update acc;

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Name',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'LAST',
        CalcItemWhereClause__c = 'PreferenceRank > 0'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    acc = [SELECT AccountNumber, AnnualRevenue, Name FROM Account];
    System.assertEquals(null, acc.AnnualRevenue, 'AnnualRevenue should have been reset: ' + acc);
  }

  @IsTest
  static void shouldResetParentValuesWithoutMatchingChildrenFromBulkRouteOverQueryLimit() {
    RollupParentResetProcessor.maxQueryRows = 0;
    Rollup.defaultControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous, IsRollupLoggingEnabled__c = true);
    Account acc = [SELECT Id FROM Account];
    acc.AccountNumber = 'someString';
    acc.AnnualRevenue = 5;
    update acc;

    Account secondParentWithValues = new Account(Name = 'Two', AnnualRevenue = 5);
    Account thirdParentWithValues = new Account(Name = 'Three', AccountNumber = '1234');
    insert new List<Account>{ secondParentWithValues, thirdParentWithValues };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'LAST',
        CalcItemWhereClause__c = 'PreferenceRank > 0'
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

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    List<Account> accounts = [SELECT AccountNumber, AnnualRevenue, Name FROM Account];
    for (Account updatedAcc : accounts) {
      System.assertEquals(null, updatedAcc.AnnualRevenue, 'AnnualRevenue should have been reset: ' + updatedAcc);
      System.assertEquals(null, updatedAcc.AccountNumber, 'AccountNumber should have been reset: ' + updatedAcc);
    }
    System.assertEquals(
      'Completed',
      [
        SELECT Status
        FROM AsyncApexJob
        WHERE JobType = 'Queueable' AND ApexClass.Name = :getNamespaceSafeClassName(RollupParentResetProcessor.class)
        LIMIT 1
      ]
      ?.Status
    );
  }

  @IsTest
  static void shouldResetParentValuesWithoutMatchingChildrenFromBulkRouteOverLimitWithBatching() {
    RollupParentResetProcessor.maxQueryRows = 0;
    Account acc = [SELECT Id FROM Account];
    acc.AccountNumber = 'someString';
    acc.AnnualRevenue = 5;
    update acc;

    Account secondParentWithValues = new Account(Name = 'Two', AnnualRevenue = 5);
    Account thirdParentWithValues = new Account(Name = 'Three', AccountNumber = '1234');
    insert new List<Account>{ secondParentWithValues, thirdParentWithValues };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'ContactPointAddress',
        RollupFieldOnCalcItem__c = 'PreferenceRank',
        LookupFieldOnCalcItem__c = 'ParentId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'LAST',
        CalcItemWhereClause__c = 'PreferenceRank > 0'
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

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    List<Account> accounts = [SELECT AnnualRevenue, Name, AccountNumber FROM Account];
    for (Account updatedAcc : accounts) {
      System.assertEquals(null, updatedAcc.AccountNumber, 'AccountNumber should have been reset: ' + updatedAcc);
      System.assertEquals(null, updatedAcc.AnnualRevenue, 'AnnualRevenue should have been reset: ' + updatedAcc);
    }
  }

  @IsTest
  static void shouldCacheRetrievedCalcItemsBetweenFullRecalcRuns() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true, ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous);
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 2, Name = 'One'),
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 3, Name = 'Two')
    };
    insert cpas;

    RollupFullBatchRecalculator fullRecalc = new RollupFullBatchRecalculator(
      'SELECT Id, PreferenceRank, ParentId FROM ContactPointAddress',
      Rollup.InvocationPoint.FROM_FULL_RECALC_LWC,
      new List<Rollup__mdt>{
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue',
          RollupOperation__c = 'SUM'
        )
      },
      ContactPointAddress.SObjectType,
      new Set<String>(),
      null
    );
    fullRecalc.addOrderBys(new List<RollupOrderBy__mdt>(), ContactPointAddress.PreferenceRank);
    // since we can't have more than one batch chunk run in the tests, but we need to test logic in the execute method
    // we'll call that method twice directly
    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[0] });
    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[1] });

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(5, acc.AnnualRevenue, 'Should have included all calc items in both runs without double-counting or incorrectly summing');
    System.assertEquals(true, Rollup.CACHED_ROLLUPS.isEmpty(), 'second execute call should have run fully');
  }

  @IsTest
  static void shouldCacheRetrievedCalcItemsBetweenFullRecalcRunsCount() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous);
    Account acc = [SELECT Id FROM Account];

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 1, Name = 'One'),
      new ContactPointAddress(ParentId = acc.Id, PreferenceRank = 1, Name = 'Two')
    };
    insert cpas;

    RollupFullBatchRecalculator fullRecalc = new RollupFullBatchRecalculator(
      'SELECT Id, PreferenceRank, ParentId FROM ContactPointAddress',
      Rollup.InvocationPoint.FROM_FULL_RECALC_LWC,
      new List<Rollup__mdt>{
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue',
          RollupOperation__c = 'Count'
        )
      },
      ContactPointAddress.SObjectType,
      new Set<String>(),
      null
    );
    fullRecalc.addOrderBys(new List<RollupOrderBy__mdt>(), ContactPointAddress.PreferenceRank);
    // since we can't have more than one batch chunk run in the tests, but we need to test logic in the execute method
    // we'll call that method twice directly
    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[0] });
    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[1] });

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue, 'Should have included all calc items in both runs without double-counting or incorrectly summing');
    System.assertEquals(true, Rollup.CACHED_ROLLUPS.isEmpty(), 'second execute call should have run fully');
  }

  @IsTest
  static void limitsFullBatchRecalcCachedItemsProperly() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous, IsRollupLoggingEnabled__c = true);
    Account parentA = [SELECT Id, OwnerId FROM Account];
    Account parentB = new Account(Name = 'Parent B');
    Account parentC = new Account(Name = 'Parent C');
    insert new List<SObject>{ parentB, parentC };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = parentA.Id, PreferenceRank = 1, Name = 'One A', UsageType = '1'),
      new ContactPointAddress(ParentId = parentB.Id, PreferenceRank = 1, Name = 'One B', UsageType = '1'),
      new ContactPointAddress(ParentId = parentC.Id, PreferenceRank = 1, Name = 'One C', UsageType = '1'),
      new ContactPointAddress(ParentId = parentA.Id, PreferenceRank = 2, Name = 'Two A', UsageType = '1'),
      new ContactPointAddress(ParentId = parentB.Id, PreferenceRank = 2, Name = 'Two B', UsageType = '1'),
      new ContactPointAddress(ParentId = parentC.Id, PreferenceRank = 2, Name = 'Two C', UsageType = '1'),
      new ContactPointAddress(ParentId = parentA.Id, PreferenceRank = 3, Name = 'Three A', UsageType = '2'),
      new ContactPointAddress(ParentId = parentB.Id, PreferenceRank = 3, Name = 'Three B', UsageType = '2'),
      new ContactPointAddress(ParentId = parentC.Id, PreferenceRank = 3, Name = 'Three C', UsageType = '2')
    };
    insert cpas;

    RollupFullBatchRecalculator fullRecalc = new RollupFullBatchRecalculator(
      'SELECT Id, PreferenceRank, ParentId FROM ContactPointAddress',
      Rollup.InvocationPoint.FROM_FULL_RECALC_LWC,
      new List<Rollup__mdt>{
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue',
          RollupOperation__c = 'SUM',
          FullRecalculationDefaultNumberValue__c = 0,
          IsFullRecordSet__c = true
        ),
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'User',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'JigsawImportLimitOverride',
          GrandparentRelationshipFieldPath__c = 'Parent.Owner.JigsawImportLimitOverride',
          RollupOperation__c = 'SUM',
          CalcItemWhereClause__c = 'ParentId = \'' + parentA.Id + '\'',
          FullRecalculationDefaultNumberValue__c = 0,
          IsFullRecordSet__c = true
        ),
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'NumberOfEmployees',
          RollupOperation__c = 'FIRST'
        ),
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'UsageType',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'Description',
          RollupOperation__c = 'MOST'
        ),
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'UsageType',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'Sic',
          RollupOperation__c = 'SOME',
          CalcItemWhereClause__c = 'PreferenceRank = 2'
        )
      },
      ContactPointAddress.SObjectType,
      new Set<String>(),
      null
    );

    Test.startTest();
    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[0], cpas[1], cpas[2] });
    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[3], cpas[4], cpas[5] });
    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[6], cpas[7], cpas[8] });
    Test.stopTest();

    for (Account parent : [SELECT AnnualRevenue, Description, NumberOfEmployees, Name, Sic FROM Account]) {
      System.assertEquals(6, parent.AnnualRevenue, parent);
      System.assertEquals('1', parent.Description, parent);
      System.assertEquals(1, parent.NumberOfEmployees, parent);
      System.assertEquals(String.valueOf(true), parent.Sic, parent);
    }
    System.assertEquals(true, Rollup.CACHED_ROLLUPS.isEmpty(), 'all deferrals should have been run');
    User parentAOwner = [SELECT Id, JigsawImportLimitOverride FROM User WHERE Id = :parentA.OwnerId];
    System.assertEquals(6, parentAOwner.JigsawImportLimitOverride);
  }

  @IsTest
  static void multipleParentRollupsMultipleBatchesStoreStateProperly() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous, IsRollupLoggingEnabled__c = true);
    Account parentA = [SELECT Id FROM Account];
    Individual parentB = new Individual(LastName = 'Parent B');
    Individual unrelatedParent = new Individual(LastName = 'Unrelated');
    Opportunity parentC = new Opportunity(Name = 'Parent C', StageName = 'Test', CloseDate = System.today());
    insert new List<SObject>{ parentB, parentC, unrelatedParent };

    List<ContactPointAddress> cpas = new List<ContactPointAddress>{
      new ContactPointAddress(ParentId = parentA.Id, PreferenceRank = 1, Name = 'One A', UsageType = '1'),
      new ContactPointAddress(ParentId = parentB.Id, PreferenceRank = 1, Name = 'One B', UsageType = '1'),
      new ContactPointAddress(ParentId = unrelatedParent.Id, PreferenceRank = 1, Name = parentC.Id, UsageType = '1'),
      new ContactPointAddress(ParentId = parentA.Id, PreferenceRank = 2, Name = 'Two A', UsageType = '1'),
      new ContactPointAddress(ParentId = parentB.Id, PreferenceRank = 8, Name = 'Two B', UsageType = '1'),
      new ContactPointAddress(ParentId = unrelatedParent.Id, PreferenceRank = 7, Name = parentC.Id, UsageType = '1'),
      new ContactPointAddress(ParentId = parentA.Id, PreferenceRank = 3, Name = 'Three A', UsageType = '2'),
      new ContactPointAddress(ParentId = parentB.Id, PreferenceRank = 3, Name = 'Three B', UsageType = '2'),
      new ContactPointAddress(ParentId = unrelatedParent.Id, PreferenceRank = 2, Name = parentC.Id, UsageType = '2')
    };
    insert cpas;

    RollupFullBatchRecalculator fullRecalc = new RollupFullBatchRecalculator(
      'SELECT Id, PreferenceRank, ParentId, Name FROM ContactPointAddress ORDER BY ParentId, Name',
      Rollup.InvocationPoint.FROM_FULL_RECALC_LWC,
      new List<Rollup__mdt>{
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue',
          RollupOperation__c = 'SUM'
        ),
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Individual',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'ConsumerCreditScore',
          RollupOperation__c = 'SUM'
        ),
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          LookupFieldOnCalcItem__c = 'Name',
          LookupObject__c = 'Opportunity',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'Amount',
          RollupOperation__c = 'MAX'
        ),
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          RollupFieldOnCalcItem__c = 'UsageType',
          LookupFieldOnCalcItem__c = 'ParentId',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'Sic',
          RollupOperation__c = 'SOME',
          CalcItemWhereClause__c = 'PreferenceRank = 2'
        )
      },
      ContactPointAddress.SObjectType,
      new Set<String>(),
      null
    );

    Test.startTest();
    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[0], cpas[1], cpas[2] });
    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[3], cpas[4], cpas[5] });
    fullRecalc.execute(null, new List<ContactPointAddress>{ cpas[6], cpas[7], cpas[8] });
    Test.stopTest();

    parentA = [SELECT AnnualRevenue, Description, NumberOfEmployees, Name, Sic FROM Account WHERE Id = :parentA.Id];
    System.assertEquals(6, parentA.AnnualRevenue);
    System.assertEquals('true', parentA.Sic);
    parentB = [SELECT ConsumerCreditScore FROM Individual WHERE Id = :parentB.Id];
    System.assertEquals(12, parentB.ConsumerCreditScore);
    parentC = [SELECT Amount FROM Opportunity WHERE Id = :parentC.Id];
    System.assertEquals(7, parentC.Amount);

    System.assertEquals(true, Rollup.CACHED_ROLLUPS.isEmpty(), 'all deferrals should have been run');
  }

  @IsTest
  static void shouldFullRecalcWithInWhereClauses() {
    RollupParentResetProcessor.maxQueryRows = 0;
    Account acc = [SELECT Id FROM Account];

    insert new List<Opportunity>{
      new Opportunity(StageName = 'firstName', CloseDate = System.today(), AccountId = acc.Id, Name = 'one', Amount = 1),
      new Opportunity(StageName = 'secondName', CloseDate = System.today(), AccountId = acc.Id, Name = 'two', Amount = 1)
    };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'StageName IN (\'firstName\', \'secondName\')'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldNotBlowUpWithDateFunctionInWhereClause() {
    Account acc = [SELECT Id FROM Account];

    insert new List<Opportunity>{
      new Opportunity(StageName = 'firstName', CloseDate = System.today(), AccountId = acc.Id, Name = 'one', Amount = 1),
      new Opportunity(StageName = 'secondName', CloseDate = System.today(), AccountId = acc.Id, Name = 'two', Amount = 1)
    };

    Rollup__mdt meta = new Rollup__mdt(
      CalcItem__c = 'Opportunity',
      RollupFieldOnCalcItem__c = 'Amount',
      LookupFieldOnCalcItem__c = 'AccountId',
      LookupObject__c = 'Account',
      LookupFieldOnLookupObject__c = 'Id',
      RollupFieldOnLookupObject__c = 'AnnualRevenue',
      RollupOperation__c = 'SUM',
      CalcItemWhereClause__c = 'CALENDAR_YEAR(CreatedDate) = ' + System.today().year()
    );

    Test.startTest();
    Rollup.performFullRecalculation(meta);
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(2, acc.AnnualRevenue);
  }

  @IsTest
  static void shouldNotRequeryForAverageItemsInFullRecalc() {
    Rollup.defaultControl = new RollupControl__mdt(ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous, MaxLookupRowsBeforeBatching__c = 2);
    Account acc = [SELECT Id FROM Account];
    Account second = new Account(Name = 'Second');
    insert second;

    insert new List<Opportunity>{
      new Opportunity(StageName = 'firstName', CloseDate = System.today(), AccountId = acc.Id, Name = 'one', Amount = 1),
      new Opportunity(StageName = 'secondName', CloseDate = System.today(), AccountId = acc.Id, Name = 'two', Amount = 3),
      new Opportunity(StageName = 'thirdName', CloseDate = System.today(), AccountId = second.Id, Name = 'three', Amount = 5),
      new Opportunity(StageName = 'thirdName', CloseDate = System.today(), AccountId = second.Id, Name = 'four', Amount = 3)
    };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'AVERAGE'
      ),
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        RollupFieldOnCalcItem__c = 'Id',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupOperation__c = 'COUNT'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    // only one of the records will have been updated since the query limit will have led to an
    // unprocessable deferral (since tests can't re-queue/batch)
    second = [SELECT AnnualRevenue, NumberOfEmployees FROM Account WHERE Id = :second.Id];
    System.assertEquals(4.00, second.AnnualRevenue);
    System.assertEquals(2.00, second.NumberOfEmployees);
  }

  @IsTest
  static void shouldNotRequeryInFullRecalcForFirstLast() {
    Rollup.defaultControl = new RollupControl__mdt(MaxLookupRowsBeforeBatching__c = 2, ShouldRunAs__c = RollupMetaPicklists.ShouldRunAs.Synchronous);
    Account acc = [SELECT Id FROM Account];
    Account second = new Account(Name = 'Second');
    insert second;

    insert new List<Opportunity>{
      new Opportunity(StageName = 'firstName', CloseDate = System.today(), AccountId = acc.Id, Name = 'one', Amount = 1),
      new Opportunity(StageName = 'secondName', CloseDate = System.today(), AccountId = acc.Id, Name = 'two', Amount = 3),
      new Opportunity(StageName = 'thirdName', CloseDate = System.today(), AccountId = second.Id, Name = 'three', Amount = 5),
      new Opportunity(StageName = 'thirdName', CloseDate = System.today(), AccountId = second.Id, Name = 'four', Amount = 3)
    };

    List<Rollup__mdt> metas = new List<Rollup__mdt>{
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'FIRST'
      ),
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        RollupFieldOnCalcItem__c = 'Id',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupObject__c = 'Account',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'NumberOfEmployees',
        RollupOperation__c = 'COUNT'
      )
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(metas, Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name());
    Test.stopTest();

    // only one of the records will have been updated since the query limit will have led to an
    // unprocessable deferral (since tests can't re-queue/batch)
    second = [SELECT AnnualRevenue, NumberOfEmployees FROM Account WHERE Id = :second.Id];
    System.assertEquals(3.00, second.AnnualRevenue);
    System.assertEquals(2.00, second.NumberOfEmployees);
  }

  @IsTest
  static void shouldWorkForTopLevelOrInWhereClause() {
    Account acc = [SELECT Id, Name FROM Account];

    insert new List<Opportunity>{
      new Opportunity(StageName = 'one', CloseDate = System.today(), AccountId = acc.Id, Name = 'one', Amount = 2),
      new Opportunity(StageName = 'two', CloseDate = System.today(), AccountId = acc.Id, Name = 'two', Amount = 2),
      new Opportunity(StageName = 'three', CloseDate = System.today(), AccountId = acc.Id, Name = 'three', Amount = 2),
      new Opportunity(StageName = 'four', CloseDate = System.today(), AccountId = acc.Id, Name = 'four', Amount = 2)
    };

    Test.startTest();
    Rollup.performFullRecalculation(
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'Amount > 0 OR CloseDate = TODAY'
      )
    );
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(8, acc.AnnualRevenue);
  }

  @IsTest
  static void parentLevelResetAffectsAllParents() {
    Account acc = [SELECT Id, Name FROM Account];
    Account nonMatching = new Account(Name = 'Non-matching', AnnualRevenue = 5);
    insert nonMatching;

    Opportunity opp = new Opportunity(Amount = 15, AccountId = acc.Id, CloseDate = System.today(), StageName = 'A', Name = 'Matching opp');
    insert opp;

    Test.startTest();
    Rollup.performFullRecalculation(
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM',
        CalcItemWhereClause__c = 'Account.Name != \'' + nonMatching.Name + '\''
      )
    );
    Test.stopTest();

    nonMatching = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :nonMatching.Id];
    System.assertEquals(null, nonMatching.AnnualRevenue, 'Non matching account should have been cleared');
    acc = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
    System.assertEquals(opp.Amount, acc.AnnualRevenue);
  }

  @IsTest
  static void parentResetDoesNotRunWhenParentsAreNotUpdatedInFullRecalc() {
    Rollup.onlyUseMockMetadata = true;
    Account acc = [SELECT Id, Name FROM Account];

    Opportunity opp = new Opportunity(Amount = 15, AccountId = acc.Id, CloseDate = System.today(), StageName = 'A', Name = 'Matching opp');
    insert opp;
    acc.AnnualRevenue = opp.Amount;
    // DML necessary here for the parent reset processor to correctly see the value as not being null
    update acc;

    Test.startTest();
    Rollup.performFullRecalculation(
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'AnnualRevenue',
        RollupOperation__c = 'SUM'
      )
    );
    Test.stopTest();

    acc = [SELECT AnnualRevenue FROM Account];
    System.assertEquals(opp.Amount, acc.AnnualRevenue);
  }

  @IsTest
  static void groupByRollupsCorrectlyQueryFieldsInFullRecalc() {
    Account acc = [SELECT Id, Description, AnnualRevenue FROM Account];
    Opportunity opp = new Opportunity(Amount = 15, AccountId = acc.Id, CloseDate = System.today(), StageName = 'A', Name = 'Matching opp');
    insert opp;
    RollupAsyncProcessor.stubParentRecords = new List<SObject>{ acc };

    Test.startTest();
    Rollup.performFullRecalculation(
      new Rollup__mdt(
        CalcItem__c = 'Opportunity',
        LookupObject__c = 'Account',
        RollupFieldOnCalcItem__c = 'Amount',
        LookupFieldOnCalcItem__c = 'AccountId',
        LookupFieldOnLookupObject__c = 'Id',
        RollupFieldOnLookupObject__c = 'Description',
        RollupOperation__c = 'SUM',
        GroupByFields__c = 'StageName',
        GroupByRowStartDelimiter__c = '<p>'
      )
    );
    Test.stopTest();

    // in actuality, platform self-closes tags on DML
    System.assertEquals('<p>A, 15.00', acc.Description);
  }

  @IsTest
  static void retainsMultiCurrencyFieldsOnParentRecords() {
    if (RollupCurrencyInfo.isMultiCurrency() == false) {
      return;
    }
    String expectedIsoCode = 'EUR';
    Account acc = (Account) RollupTestUtils.queryRecord(Account.SObjectType, new List<Schema.SObjectField>());
    System.assertNotEquals(null, acc.get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME), 'Test has started under the wrong conditions');
    acc.put(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME, expectedIsoCode);

    RollupDeferredFullRecalcProcessor processor = new RollupDeferredFullRecalcProcessor(
      new List<Rollup__mdt>{ new Rollup__mdt(RollupFieldOnLookupObject__c = 'Description', LookupObject__c = 'Account') },
      Schema.Contact.SObjectType,
      'SELECT Id, CurrencyIsoCode\nFROM Contact WHERE Id != null',
      new Set<String>(),
      Rollup.InvocationPoint.FROM_FULL_RECALC_LWC,
      null
    );

    List<Account> storedAccounts = new List<Account>{ acc };
    processor.storeParentFieldsToClear(storedAccounts);
    List<Account> newAccounts = new List<Account>{ new Account(Id = RollupTestUtils.createId(Account.SObjectType)), acc };
    newAccounts[0].put(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME, 'USD');
    processor.processParentFieldsToReset(newAccounts);

    System.assertEquals(expectedIsoCode, acc.get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME), 'Currency ISO code should not have been cleared');
    System.assertNotEquals(null, newAccounts[0].get(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME));
  }

  @IsTest
  static void correctlyHandlesMultipleDeferredFullRecalcs() {
    Account acc = [SELECT Id FROM Account];
    ContactPointAddress one = new ContactPointAddress(ParentId = acc.Id, Name = 'child one', PreferenceRank = 25);
    ContactPointAddress two = new ContactPointAddress(ParentId = acc.Id, Name = 'child two', PreferenceRank = 50);
    insert new List<ContactPointAddress>{ one, two };

    Set<String> recordIds = new Set<String>{ String.valueOf(one.Id), String.valueOf(two.Id) };

    Test.startTest();
    Rollup.batch(
      new List<Rollup>{
        new DeferredContactPointAddressRollup(
            new List<Rollup__mdt>{
              new Rollup__mdt(
                CalcItem__c = 'ContactPointAddress',
                RollupFieldOnCalcItem__c = 'Id',
                LookupFieldOnCalcItem__c = 'ParentId',
                LookupObject__c = 'Account',
                LookupFieldOnLookupObject__c = 'Id',
                RollupFieldOnLookupObject__c = 'NumberOfEmployees',
                RollupOperation__c = 'COUNT'
              ),
              new Rollup__mdt(
                CalcItem__c = 'ContactPointAddress',
                RollupFieldOnCalcItem__c = 'Id',
                LookupFieldOnCalcItem__c = 'ParentId',
                LookupObject__c = 'Account',
                LookupFieldOnLookupObject__c = 'Id',
                RollupFieldOnLookupObject__c = 'Name',
                RollupOperation__c = 'MAX'
              )
            },
            recordIds
          )
          .modifyMetadata(new Rollup__mdt()),
        new DeferredContactPointAddressRollup(
          new List<Rollup__mdt>{
            new Rollup__mdt(
              CalcItem__c = 'ContactPointAddress',
              RollupFieldOnCalcItem__c = 'PreferenceRank',
              LookupFieldOnCalcItem__c = 'ParentId',
              LookupObject__c = 'Account',
              LookupFieldOnLookupObject__c = 'Id',
              RollupFieldOnLookupObject__c = 'AnnualRevenue',
              RollupOperation__c = 'SUM'
            ),
            new Rollup__mdt(
              CalcItem__c = 'ContactPointAddress',
              RollupFieldOnCalcItem__c = 'Name',
              LookupFieldOnCalcItem__c = 'ParentId',
              LookupObject__c = 'Account',
              LookupFieldOnLookupObject__c = 'Id',
              RollupFieldOnLookupObject__c = 'Description',
              RollupOperation__c = 'CONCAT'
            )
          },
          recordIds
        )
      }
    );
    Test.stopTest();

    acc = [SELECT NumberOfEmployees, AnnualRevenue FROM Account];
    System.assertEquals(2, acc.NumberOfEmployees);
    System.assertEquals(one.PreferenceRank + two.PreferenceRank, acc.AnnualRevenue);
  }

  @IsTest
  static void addsCabooseForMultipleFullRecalcsToDifferentParents() {
    // when there are multiple children types passed to Rollup.performBulkFullRecalc (or any other method ending in a full recalc),
    // and there are multiple instances of the full batch recalcs that are present in the list of rollups
    Rollup.defaultControl = new RollupControl__mdt(MaxRollupRetries__c = 100, MaxLookupRowsBeforeBatching__c = 2, IsRollupLoggingEnabled__c = true);
    Rollup.onlyUseMockMetadata = true;

    Account parentOne = [SELECT Id FROM Account];
    ContactPointAddress childOne = new ContactPointAddress(ParentId = parentOne.Id, Name = 'child one', PreferenceRank = 25);
    Account parentTwo = new Account(Name = 'Parent Two');
    insert new List<SObject>{ childOne, parentTwo };

    // with two different parents this one should be a batch
    insert new List<Opportunity>{
      new Opportunity(AccountId = parentOne.Id, StageName = 'One', CloseDate = System.today(), Name = 'Another child rollup', Amount = 5),
      new Opportunity(AccountId = parentTwo.Id, StageName = 'Two', CloseDate = System.today(), Name = 'Child rollup two', Amount = 10)
    };

    // same thing here; we need TWO different batches to prove that this is working (because getAsyncRollup() shortcuts to the first rollup in the list when
    // there is only one AND it's a full recalc, but we need this to work for multiple batch full recalcs at once)
    insert new List<Contact>{
      new Contact(AccountId = parentOne.Id, LastName = 'Concat'),
      new Contact(AccountId = parentOne.Id, LastName = 'One'),
      new Contact(AccountId = parentTwo.Id, LastName = 'Concat'),
      new Contact(AccountId = parentTwo.Id, LastName = 'Two')
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(
      new List<Rollup__mdt>{
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          LookupFieldOnCalcItem__c = 'ParentId',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          RollupOperation__c = 'SUM',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue'
        ),
        new Rollup__mdt(
          CalcItem__c = 'Opportunity',
          LookupFieldOnCalcItem__c = 'AccountId',
          RollupFieldOnCalcItem__c = 'Amount',
          RollupOperation__c = 'MAX',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'NumberOfEmployees'
        ),
        new Rollup__mdt(
          CalcItem__c = 'Contact',
          LookupFieldOnCalcItem__c = 'AccountId',
          RollupFieldOnCalcItem__c = 'Name',
          RollupOperation__c = 'CONCAT',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'Description'
        )
      },
      Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name()
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable' AND ApexClass.Name = :getNamespaceSafeClassName(RollupFullBatchRecalculator.class)],
      'Exactly two batch full recalcs should have run'
    );
    parentOne = [SELECT AnnualRevenue, Description, NumberOfEmployees FROM Account WHERE Id = :parentOne.Id];
    Assert.areEqual(childOne.PreferenceRank, parentOne.AnnualRevenue);
    Assert.areEqual('Concat, One', parentOne.Description);
    Assert.areEqual(5, parentOne.NumberOfEmployees);
    parentTwo = [SELECT AnnualRevenue, Description, NumberOfEmployees FROM Account WHERE Id = :parentTwo.Id];
    Assert.areEqual(null, parentTwo.AnnualRevenue);
    Assert.areEqual('Concat, Two', parentTwo.Description);
    Assert.areEqual(10, parentTwo.NumberOfEmployees);
    Assert.areEqual(0, [SELECT COUNT() FROM RollupState__c], '' + [SELECT COUNT(Id), RelatedJobId__c FROM RollupState__c GROUP BY RelatedJobId__c]);
  }

  @IsTest
  static void addsCabooseForMultipleFullRecalcsToDifferentParentsWithoutOtherRollups() {
    // when there are multiple children types passed to Rollup.performBulkFullRecalc (or any other method ending in a full recalc),
    // and there are multiple instances of the full batch recalcs that are present in the list of rollups
    Rollup.defaultControl = new RollupControl__mdt(MaxRollupRetries__c = 100, MaxLookupRowsBeforeBatching__c = 2, IsRollupLoggingEnabled__c = true);
    Rollup.onlyUseMockMetadata = true;

    Account parentOne = [SELECT Id FROM Account];
    Account parentTwo = new Account(Name = 'Parent Two');
    insert parentTwo;

    // with two different parents this one should be a batch
    insert new List<Opportunity>{
      new Opportunity(AccountId = parentOne.Id, StageName = 'One', CloseDate = System.today(), Name = 'Another child rollup', Amount = 5),
      new Opportunity(AccountId = parentTwo.Id, StageName = 'Two', CloseDate = System.today(), Name = 'Child rollup two', Amount = 10)
    };

    // same thing here; we need TWO different batches to prove that this is working (because getAsyncRollup() shortcuts to the first rollup in the list when
    // there is only one AND it's a full recalc, but we need this to work for multiple batch full recalcs at once)
    ContactPointAddress childOne = new ContactPointAddress(ParentId = parentOne.Id, Name = 'child one', PreferenceRank = 25);
    insert new List<ContactPointAddress>{
      childOne,
      new ContactPointAddress(ParentId = parentOne.Id, Name = 'Concat'),
      new ContactPointAddress(ParentId = parentOne.Id, Name = 'One'),
      new ContactPointAddress(ParentId = parentTwo.Id, Name = 'Concat'),
      new ContactPointAddress(ParentId = parentTwo.Id, Name = 'Two')
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(
      new List<Rollup__mdt>{
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          LookupFieldOnCalcItem__c = 'ParentId',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          RollupOperation__c = 'SUM',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue'
        ),
        new Rollup__mdt(
          CalcItem__c = 'Opportunity',
          LookupFieldOnCalcItem__c = 'AccountId',
          RollupFieldOnCalcItem__c = 'Amount',
          RollupOperation__c = 'MAX',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'NumberOfEmployees'
        ),
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          LookupFieldOnCalcItem__c = 'ParentId',
          RollupFieldOnCalcItem__c = 'Name',
          RollupOperation__c = 'CONCAT',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'Description'
        )
      },
      Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name()
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable' AND ApexClass.Name = :getNamespaceSafeClassName(RollupFullBatchRecalculator.class)],
      'Exactly two batch full recalcs should have run'
    );
    parentOne = [SELECT AnnualRevenue, Description, NumberOfEmployees FROM Account WHERE Id = :parentOne.Id];
    Assert.areEqual(childOne.PreferenceRank, parentOne.AnnualRevenue);
    Assert.areEqual('Concat, One, child one', parentOne.Description);
    Assert.areEqual(5, parentOne.NumberOfEmployees);
    parentTwo = [SELECT AnnualRevenue, Description, NumberOfEmployees FROM Account WHERE Id = :parentTwo.Id];
    Assert.areEqual(null, parentTwo.AnnualRevenue);
    Assert.areEqual('Concat, Two', parentTwo.Description);
    Assert.areEqual(10, parentTwo.NumberOfEmployees);
    Assert.areEqual(0, [SELECT COUNT() FROM RollupState__c]);
  }

  @IsTest
  static void allowsMultipleRollupsToSameFieldWithDifferentBatches() {
    // an interesting one because it's again an implementation detail - this time,
    // of the batch "caboose" process. if the full recalc is BELOW the batch limit,
    // the queueable will already correctly handle everything since the shared parent field will only be reset once.
    // batch queueables, on the other hand, would otherwise simply see the existing value on the parent as something
    // that needs to be cleared out
    Rollup.defaultControl = new RollupControl__mdt(
      MaxRollupRetries__c = 100,
      MaxLookupRowsBeforeBatching__c = 1,
      IsRollupLoggingEnabled__c = true,
      BatchChunkSize__c = 3
    );
    Rollup.onlyUseMockMetadata = true;
    Account parent = [SELECT Id FROM Account];

    insert new List<SObject>{
      new ContactPointAddress(ParentId = parent.Id, Name = 'child 1 first object', PreferenceRank = 25),
      new Opportunity(AccountId = parent.Id, StageName = 'One', CloseDate = System.today(), Name = 'child 1 second object', Amount = 5),
      new Opportunity(AccountId = parent.Id, StageName = 'Two', CloseDate = System.today(), Name = 'child 2 second object', Amount = 10)
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(
      new List<Rollup__mdt>{
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          LookupFieldOnCalcItem__c = 'ParentId',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          RollupOperation__c = 'SUM',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue'
        ),
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          LookupFieldOnCalcItem__c = 'ParentId',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          RollupOperation__c = 'MIN',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'NumberOfEmployees'
        ),
        new Rollup__mdt(
          CalcItem__c = 'Opportunity',
          LookupFieldOnCalcItem__c = 'AccountId',
          RollupFieldOnCalcItem__c = 'Amount',
          RollupOperation__c = 'SUM',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue'
        )
      },
      Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name()
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable' AND ApexClass.Name = :getNamespaceSafeClassName(RollupFullBatchRecalculator.class)],
      'Test requires RollupFullBatchRecalculator to have been used'
    );
    parent = [SELECT AnnualRevenue, NumberOfEmployees FROM Account WHERE Id = :parent.Id];
    Assert.areEqual(40, parent.AnnualRevenue, 'Both children types should have correctly summed to one field in batch recalc');
    Assert.areEqual(25, parent.NumberOfEmployees, 'Additional field on parent should have been queried successfully in second rollup');
    Assert.areEqual(0, [SELECT COUNT() FROM RollupState__c]);
  }

  @IsTest
  static void allowsMultipleRollupsToSameFieldWithQueueable() {
    Rollup.onlyUseMockMetadata = true;
    Account parent = [SELECT Id FROM Account];
    Account secondParent = new Account(Name = 'Second');
    insert secondParent;

    insert new List<SObject>{
      new ContactPointAddress(ParentId = parent.Id, Name = 'child 1 first object', PreferenceRank = 25),
      new Opportunity(AccountId = parent.Id, StageName = 'One', CloseDate = System.today(), Name = 'child 1 second object', Amount = 5),
      new Opportunity(AccountId = parent.Id, StageName = 'Two', CloseDate = System.today(), Name = 'child 2 second object', Amount = 10),
      new Opportunity(AccountId = secondParent.Id, StageName = 'Two', CloseDate = System.today(), Name = 'child 1 second object second parent', Amount = 10)
    };

    Test.startTest();
    Rollup.performBulkFullRecalc(
      new List<Rollup__mdt>{
        new Rollup__mdt(
          CalcItem__c = 'ContactPointAddress',
          LookupFieldOnCalcItem__c = 'ParentId',
          RollupFieldOnCalcItem__c = 'PreferenceRank',
          RollupOperation__c = 'SUM',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue'
        ),
        new Rollup__mdt(
          CalcItem__c = 'Opportunity',
          LookupFieldOnCalcItem__c = 'AccountId',
          RollupFieldOnCalcItem__c = 'Amount',
          RollupOperation__c = 'SUM',
          LookupObject__c = 'Account',
          LookupFieldOnLookupObject__c = 'Id',
          RollupFieldOnLookupObject__c = 'AnnualRevenue'
        )
      },
      Rollup.InvocationPoint.FROM_FULL_RECALC_LWC.name()
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable' AND ApexClass.Name = :getNamespaceSafeClassName(RollupDeferredFullRecalcProcessor.class)],
      JSON.serializePretty([SELECT JobType, ApexClass.Name FROM AsyncApexJob])
    );
    parent = [SELECT AnnualRevenue FROM Account WHERE Id = :parent.Id];
    Assert.areEqual(40, parent.AnnualRevenue, 'Both children types should have correctly summed to one field in full recalc');
  }

  private static String getNamespaceSafeClassName(Type intendedClass) {
    List<String> classNameParts = intendedClass.getName().split('\\.');
    if (classNameParts.size() > 1) {
      classNameParts.remove(0);
    }
    return classNameParts[0];
  }

  private class DeferredContactPointAddressRollup extends RollupDeferredFullRecalcProcessor {
    public DeferredContactPointAddressRollup(List<Rollup__mdt> meta, Set<String> recordIds) {
      super(
        meta,
        ContactPointAddress.SObjectType,
        'SELECT Id, ParentId, PreferenceRank, Name FROM ContactPointAddress',
        recordIds,
        Rollup.InvocationPoint.FROM_APEX,
        null
      );
      this.isNoOp = false;
      this.queryCount = 1;
    }
  }
}
