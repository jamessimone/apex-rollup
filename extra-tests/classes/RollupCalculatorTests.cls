@SuppressWarnings('PMD.NcssTypeCount')
@IsTest
private class RollupCalculatorTests {
  // use these tests when DML is not required, or only *light* DML is necessary

  @TestSetup
  static void setup() {
    insert new Account(Name = RollupCalculatorTests.class.getName());
  }

  /** FIRST / LAST operations */
  @IsTest
  static void shouldReturnNullWhenNoCalcItemsFirst() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'CloseDate');
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    calc.performRollup(new List<Opportunity>(), new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void fullRecalcDefaultUsedInsteadOfNullWhenSupplied() {
    Integer defaultVal = 0;
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(FullRecalculationDefaultNumberValue__c = defaultVal), 'CloseDate');
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    calc.performRollup(new List<Opportunity>(), new Map<Id, SObject>());

    System.assertEquals(defaultVal, calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnFirstValueBasedOnMetadataField() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'CloseDate');
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    // the important part is that the middle item is the one used, to prove that sorting occurred
    // this will be true for all the first/last tests in this class
    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 1, CloseDate = System.today().addDays(2)),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 2, CloseDate = System.today()),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 15, CloseDate = System.today().addDays(1))
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(2, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnLastValueBasedOnMetadataField() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'CloseDate');
    RollupCalculator calc = getCalculator(0, Rollup.Op.LAST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 1, CloseDate = System.today().addDays(-15)),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 2, CloseDate = System.today()),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 15, CloseDate = System.today().addDays(-2))
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(2, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnFirstValueIfOtherOrderByValueIsNull() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'CloseDate');
    metadata.RollupOrderBys__r[0].NullSortOrder__c = RollupMetaPicklists.NullSortOrder.NullsLast;
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 1),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 2, CloseDate = System.today()),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 15, CloseDate = System.today().addDays(2))
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(2, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnMiddleValueForFirst() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'CloseDate');
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    Date today = System.today();
    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 1, CloseDate = today.addDays(1)),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 2, CloseDate = today),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 15, CloseDate = today.addDays(1))
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(2, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnFirstValueWhenMiddleAndLastAreNull() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'CloseDate');
    metadata.RollupOrderBys__r[0].NullSortOrder__c = RollupMetaPicklists.NullSortOrder.NullsLast;
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 1, CloseDate = System.today()),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 2),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 15)
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(1, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnLastValueIfOtherOrderByValueIsNull() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'CloseDate');
    metadata.RollupOrderBys__r[0].NullSortOrder__c = RollupMetaPicklists.NullSortOrder.NullsLast;
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 1),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 2, CloseDate = System.today()),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 15)
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(2, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void shouldNotSortAtAllIfOrderByValuesAreNull() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'CloseDate');
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    List<Opportunity> opps = new List<Opportunity>{
      new Opportunity(Id = '0066g00003VDGbF001', Amount = 1),
      new Opportunity(Id = '0066g00003VDGbF002', Amount = 2),
      new Opportunity(Id = '0066g00003VDGbF003', Amount = 15)
    };

    calc.performRollup(opps, new Map<Id, SObject>());

    System.assertEquals(opps[0].Amount, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnFirstString() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'Name');
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 1, Name = 'b'),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 2, Name = 'a'),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 15, Name = 'c')
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(2, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnLastString() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'Name');
    RollupCalculator calc = getCalculator(0, Rollup.Op.LAST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 1, Name = 'b'),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 2, Name = 'c'),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 15, Name = 'a')
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(2, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnFirstNumber() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'Amount');
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 2),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 1),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 15)
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(1, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnLastNumber() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'Amount');
    RollupCalculator calc = getCalculator(0, Rollup.Op.LAST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 2),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 16),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 1)
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(16, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void regressionShouldRollupFirstLastWithQueriedOrderBy() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'Name');
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '0011g00003VDGbF002', Account.Id);

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, Name = 'b'),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 16, Name = 'a'),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 1, Name = 'c')
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(16, (Decimal) calc.getReturnValue());
  }

  @IsTest
  static void shouldIncludeStateForFirstLast() {
    String lookupKey = '0011g00003VDGbF002';
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'Name');
    RollupCalculator calc = getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, lookupKey, Account.Id);
    RollupState outerState = new RollupState();
    RollupState.SObjectInfo info = (RollupState.SObjectInfo) outerState.getState(lookupKey, metadata, RollupState.SObjectInfo.class);
    info.setItem(new Opportunity(Name = 'a', Amount = 3));
    calc.setState(outerState);

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, Name = 'c'),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 16, Name = 'b'),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 1, Name = 'c')
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(3, calc.getReturnValue(), 'Should use state properly');
  }

  @IsTest
  static void defaultValueWhenNoMatchesIsIgnoredForFullRecalc() {
    Object priorValue = 50;
    RollupCalculator calc = getCalculator(
      priorValue,
      Rollup.Op.SUM,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(FullRecalculationDefaultNumberValue__c = 0),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );
    calc.setFullRecalc(true);
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 0);
    Opportunity oppTwo = new Opportunity(Amount = 0);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(priorValue, calc.getReturnValue());
  }

  // AVERAGE tests

  @IsTest
  static void shouldReturnNulltWhenNoCalcItemsAverage() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(), 'CloseDate');
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.Average,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    calc.performRollup(new List<Opportunity>(), new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnFullRecalcDefaultWhenNoCalcItemsAverage() {
    Rollup__mdt metadata = configureOrderByMetadata(new Rollup__mdt(FullRecalculationDefaultNumberValue__c = 5), 'CloseDate');
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.Average,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    calc.performRollup(new List<Opportunity>(), new Map<Id, SObject>());

    System.assertEquals(metadata.FullRecalculationDefaultNumberValue__c, calc.getReturnValue());
  }

  @IsTest
  static void shouldNotTryToAverageNull() {
    Rollup__mdt metadata = new Rollup__mdt();
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.AVERAGE,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 2),
        new Opportunity(Id = '0066g00003VDGbF002'),
        new Opportunity(Id = '0066g00003VDGbF003'),
        new Opportunity(Id = '0066g00003VDGbF004', Amount = 2)
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(1, calc.getReturnValue(), 'Nulls should be treated as zeros for average!');
  }

  @IsTest
  static void shouldCorrectlyAverageForTasks() {
    Account acc = [SELECT Id FROM Account];

    Task one = new Task(WhatId = acc.Id, Subject = 'One', CallDurationInSeconds = 3, Id = RollupTestUtils.createId(Task.SObjectType));
    Task two = new Task(WhatId = acc.Id, CallDurationInSeconds = 5, Subject = 'Two', Id = RollupTestUtils.createId(Task.SObjectType));

    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.AVERAGE,
      Task.CallDurationInSeconds,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Task'),
      acc.Id,
      Task.AccountId
    );
    calc.performRollup(new List<Task>{ one, two }, new Map<Id, SObject>());

    System.assertEquals(4, calc.getReturnValue());
  }

  // COUNT tests

  @IsTest
  static void shouldReturnNewValOnCountChangeIfReparenting() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.UPDATE_COUNT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>{ opp.Id => new Opportunity(AccountId = '0016g00003VDGbF002') });

    System.assertEquals(1, (Decimal) calc.getReturnValue(), 'If record is reparented, it should count towards count for new record!');
  }

  @IsTest
  static void shouldReturnNullOnFullRecalcIfNoMatchingItemsCount() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.COUNT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount != ' + opp.Amount, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnNullOnFullRecalcIfNoItemsPresentCount() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.COUNT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    calc.performRollup(new List<SObject>(), new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnZeroOnFullRecalcIfNoMatchingItemsCountDistinct() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.COUNT_DISTINCT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount != ' + opp.Amount, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(0, calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnDefaultValueOnFullRecalcIfNoMatchingItemsCountDistinct() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.COUNT_DISTINCT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(FullRecalculationDefaultNumberValue__c = 15),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount != ' + opp.Amount, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(15, calc.getReturnValue());
  }

  @IsTest
  static void resetsDefaultValuesBetweenCountDistinctRuns() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.COUNT_DISTINCT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2);

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(1, calc.getReturnValue());

    calc.setDefaultValues('0011g00003VDGbF001', 5); // for COUNT_DISTINCT the prior value isn't used since we assume each one is a full recalc
    calc.performRollup(new List<Opportunity>{ opp, new Opportunity(Amount = 3) }, new Map<Id, SObject>());

    System.assertEquals(2, calc.getReturnValue());
  }

  @IsTest
  static void shouldNotCountNullsForCountDistinctDelete() {
    Account acc = [SELECT Id FROM Account];
    insert new Opportunity(CloseDate = System.today(), StageName = 'Hi', AccountId = acc.Id, Name = 'null amount');
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.DELETE_COUNT_DISTINCT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      acc.Id,
      Opportunity.AccountId
    );

    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = acc.Id);
    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue(), 'Null amount should be excluded');
  }

  @IsTest
  static void shouldNotDoubleCountDistinctForDeletions() {
    Account acc = [SELECT Id FROM Account];
    insert new Contact(LastName = 'Count Distinct', AccountId = acc.Id);

    RollupCalculator calc = getCalculator(
      3,
      Rollup.Op.DELETE_COUNT_DISTINCT,
      Contact.Id,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Contact'),
      acc.Id,
      Contact.AccountId
    );
    calc.performRollup(
      new List<SObject>{ new Contact(Id = RollupTestUtils.createId(Contact.SObjectType)), new Contact(Id = RollupTestUtils.createId(Contact.SObjectType)) },
      new Map<Id, SObject>()
    );

    System.assertEquals(1, calc.getReturnValue(), 'Should not double count any deleted items');
  }

  @IsTest
  static void shouldProperlyRemoveCountDistinctOnUpdateIfOldItemMatchesAndNewOneDoesNot() {
    Account acc = [SELECT Id FROM Account];
    Opportunity opp = new Opportunity(AccountId = acc.Id, CloseDate = System.today(), StageName = 'Hi', Name = 'Count Distinct', Amount = 5);
    insert opp;

    Opportunity newerOpp = opp.clone(true, true);
    newerOpp.Amount = 0;

    RollupCalculator calc = getCalculator(
      1,
      Rollup.Op.UPDATE_COUNT_DISTINCT,
      Opportunity.Id,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      acc.Id,
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));
    Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>{ opp.Id => opp };

    calc.performRollup(new List<Opportunity>{ newerOpp }, oldOppMap);

    System.assertEquals(0, calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnCountIfRollupValueUnchangedButEvalStatusHas() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.UPDATE_COUNT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.Amount = 1;
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount != ' + oldOpp.Amount, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>{ oldOpp.Id => oldOpp });
    System.assertEquals(1, calc.getReturnValue(), 'Count should be returned if item was previously excluded but now isn\t!');
  }

  @IsTest
  static void shouldAllowIncrementOnUpdateIfOldValueIsDefault() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.UPDATE_COUNT,
      Opportunity.Name,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = 'Something else', AccountId = '0011g00003VDGbF002');
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.Name = ''; // string default

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>{ oldOpp.Id => oldOpp });
    System.assertEquals(1, calc.getReturnValue(), 'Count should be recorded properly if old value was default and new value exists');
  }

  @IsTest
  static void shouldDecrementIfOldCalcItemMatchesAndNewOneDoesNot() {
    RollupCalculator calc = getCalculator(
      1,
      Rollup.Op.UPDATE_COUNT,
      Opportunity.Name,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    // use two calc items to ensure full recalc AND for loop in calculator are hit
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = 'Something else', AccountId = '0011g00003VDGbF002');
    Opportunity two = new Opportunity(Id = '0066g00003VDGbF002', Name = 'matching', AccountId = '0011g00003VDGbF002');
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.Name = 'matching';
    Opportunity secondOldOpp = two.clone(true, true);
    secondOldOpp.Name = '';
    calc.setEvaluator(RollupEvaluator.getWhereEval('Name = \'' + oldOpp.Name + '\'', Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp, two }, new Map<Id, SObject>{ oldOpp.Id => oldOpp, two.Id => secondOldOpp });

    System.assertEquals(1, calc.getReturnValue(), 'Count should properly decrement when old item matches and new one does not');
  }

  @IsTest
  static void shouldDecrementBooleanCountProperly() {
    RollupCalculator calc = getCalculator(
      1,
      Rollup.Op.UPDATE_COUNT,
      ContactPointAddress.IsPrimary,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'ContactPointAddress'),
      '0011g00003VDGbF002',
      ContactPointAddress.ParentId
    );

    ContactPointAddress cpa = new ContactPointAddress(IsPrimary = false, Id = RollupTestUtils.createId(ContactPointAddress.SObjectType));
    calc.performRollup(new List<SObject>{ cpa }, new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(IsPrimary = true) });

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void shouldConsiderDateChangesCorrectlyCount() {
    RollupCalculator calc = getCalculator(
      1,
      Rollup.Op.UPDATE_COUNT,
      Opportunity.CloseDate,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    Opportunity opp = new Opportunity(CloseDate = System.today(), Id = RollupTestUtils.createId(Opportunity.SObjectType));
    calc.performRollup(new List<SObject>{ opp }, new Map<Id, SObject>{ opp.Id => new Opportunity(CloseDate = opp.CloseDate.addDays(-1)) });

    System.assertEquals(1, calc.getReturnValue());
  }

  // MOST tests

  @IsTest
  static void mostReturnsNullIfNoMatchingItems() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.MOST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount != ' + opp.Amount, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void mostReturnsDefaultValWhenSuppliedIfNoMatchingItems() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.MOST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(FullRecalculationDefaultNumberValue__c = 5),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount != ' + opp.Amount, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(5, calc.getReturnValue());
  }

  @IsTest
  static void mostCalculatesSequentialValuesCorrectly() {
    RollupCalculator calc = getCalculator(
      null,
      Rollup.Op.MOST,
      Opportunity.CloseDate,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    Opportunity opp = new Opportunity(CloseDate = System.today(), Id = RollupTestUtils.createId(Opportunity.SObjectType));
    calc.performRollup(new List<SObject>{ opp }, new Map<Id, SObject>());

    System.assertEquals(opp.CloseDate, calc.getReturnValue());

    opp.CloseDate = opp.CloseDate.addDays(-1);
    calc.performRollup(new List<SObject>{ opp }, new Map<Id, SObject>());

    System.assertEquals(opp.CloseDate, calc.getReturnValue());
  }

  @IsTest
  static void mostRespectsStateValues() {
    Account acc = [SELECT Id FROM Account];
    Integer priorVal = 50;
    RollupState outerState = new RollupState();
    Rollup__mdt metaKey = new Rollup__mdt();
    RollupState.MostInfo info = (RollupState.MostInfo) outerState.getState(acc.Id, metaKey, RollupState.MostInfo.class);
    info.setValues(2, priorVal);

    RollupCalculator calc = getCalculator(
      priorVal,
      Rollup.Op.MOST,
      ContactPointAddress.PreferenceRank,
      Account.AnnualRevenue,
      metaKey,
      acc.Id,
      ContactPointAddress.ParentId
    );
    calc.setState(outerState);

    ContactPointAddress target = new ContactPointAddress(
      PreferenceRank = 75,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType),
      ParentId = acc.Id
    );
    calc.performRollup(new List<SObject>{ target }, new Map<Id, SObject>());

    System.assertEquals(priorVal, calc.getReturnValue());
  }

  // SUM tests

  @IsTest
  static void shouldReturnNullOnFullRecalcIfNoMatchingItemsSum() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.SUM,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount != ' + opp.Amount, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void sumsDistinctWhenFlagged() {
    Id stubParentId = RollupTestUtils.createId(Schema.Account.SObjectType);
    Object parentStartingValue = 0;
    RollupCalculator calc = getCalculator(
      parentStartingValue,
      Rollup.Op.SUM,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(IsDistinct__c = true),
      stubParentId,
      Opportunity.AccountId
    );

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = RollupTestUtils.createId(Schema.Opportunity.SObjectType), Amount = 2, AccountId = stubParentId),
        new Opportunity(Id = RollupTestUtils.createId(Schema.Opportunity.SObjectType), Amount = 2, AccountId = stubParentId)
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(2, calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnSumIfRollupValueUnchangedButEvalStatusHas() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.UPDATE_SUM,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    Opportunity oldOpp = opp.clone(true, true);
    oldOpp.Amount = 1;
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount != ' + oldOpp.Amount, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>{ oldOpp.Id => oldOpp });
    System.assertEquals(2, calc.getReturnValue(), 'Sum should be returned if item was previously excluded but now isn\t!');
  }

  @IsTest
  static void shouldProperlyRemoveSumOnUpdateIfOldItemMatchesAndNewOneDoesNot() {
    Account acc = [SELECT Id FROM Account];
    Opportunity opp = new Opportunity(AccountId = acc.Id, CloseDate = System.today(), StageName = 'Hi', Name = 'Count Distinct', Amount = 5);
    insert opp;

    Opportunity newerOpp = opp.clone(true, true);
    newerOpp.Amount = 0;

    RollupCalculator calc = getCalculator(5, Rollup.Op.UPDATE_SUM, Opportunity.Amount, Account.AnnualRevenue, new Rollup__mdt(), acc.Id, Opportunity.AccountId);
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));
    Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>{ opp.Id => opp };

    calc.performRollup(new List<Opportunity>{ newerOpp }, oldOppMap);

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void sumForFullRecalcIgnoresDiffForUpdates() {
    Opportunity opp = new Opportunity(Id = RollupTestUtils.createId(Opportunity.SObjectType), Amount = 5);

    RollupCalculator calc = getCalculator(0, Rollup.Op.UPDATE_SUM, Opportunity.Amount, Account.AnnualRevenue, new Rollup__mdt(), '', Opportunity.AccountId);
    calc.setFullRecalc(true);
    Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Amount = 2) };

    calc.performRollup(new List<Opportunity>{ opp }, oldOppMap);

    System.assertEquals(opp.Amount, calc.getReturnValue());
  }

  @IsTest
  static void correctlySumsMulticurrencyOnUpdate() {
    if (RollupCurrencyInfo.isMultiCurrency() == false) {
      return;
    }

    RollupCurrencyInfo mockUsdInfo = new RollupCurrencyInfo();
    mockUsdInfo.ConversionRate = 1;
    mockUsdInfo.DecimalPlaces = 2;
    mockUsdInfo.IsoCode = 'USD';
    RollupCurrencyInfo mockEurInfo = new RollupCurrencyInfo();
    mockEurInfo.ConversionRate = .64;
    mockEurInfo.DecimalPlaces = 2;
    mockEurInfo.IsoCode = 'EUR';
    RollupCurrencyInfo.mockCurrencyData = new List<RollupCurrencyInfo>{ mockUsdInfo, mockEurInfo };

    RollupCalculator calc = getCalculator(
      1.5625,
      Rollup.Op.UPDATE_SUM,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '',
      Opportunity.AccountId
    );
    Account parent = new Account();
    parent.put(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME, mockUsdInfo.IsoCode);
    calc.setMultiCurrencyInfo(parent);
    Opportunity opp = new Opportunity(Id = RollupTestUtils.createId(Opportunity.SObjectType), Amount = 0);
    opp.put(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME, mockEurInfo.IsoCode);
    Opportunity oldOpp = opp.clone(true);
    oldOpp.Amount = 1;
    Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>{ opp.Id => oldOpp };

    calc.performRollup(new List<Opportunity>{ opp }, oldOppMap);

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void correctlyAppliesStatefulSums() {
    Rollup__mdt metaKey = new Rollup__mdt();
    String accountKey = '0011g00003VDGbF002';
    Integer value = 1;
    RollupCalculator calc = getCalculator(null, Rollup.Op.SUM, Opportunity.Amount, Account.AnnualRevenue, metaKey, accountKey, Opportunity.AccountId);
    RollupState outerState = new RollupState();
    RollupState.GenericInfo info = (RollupState.GenericInfo) outerState.getState(accountKey, metaKey, RollupState.GenericInfo.class);
    info.value = value;
    calc.setState(outerState);

    Opportunity one = new Opportunity(Id = '0066g00003VDGbF001', Amount = 5, AccountId = accountKey);
    Opportunity two = new Opportunity(Id = '0066g00003VDGbF002', Amount = 5, AccountId = accountKey);

    calc.performRollup(new List<Opportunity>{ one, two }, new Map<Id, SObject>());

    System.assertEquals(one.Amount + two.Amount + value, calc.getReturnValue());
    System.assertEquals(one.Amount + two.Amount + value, info.value);
  }

  @IsTest
  static void doesNotResetParentValueWhenOnlyStatefulSumMatches() {
    Rollup__mdt metaKey = new Rollup__mdt();
    String accountKey = '0011g00003VDGbF002';
    Integer value = 1;
    RollupCalculator calc = getCalculator(null, Rollup.Op.SUM, Opportunity.Amount, Account.AnnualRevenue, metaKey, accountKey, Opportunity.AccountId);
    RollupState outerState = new RollupState();
    RollupState.GenericInfo info = (RollupState.GenericInfo) outerState.getState(accountKey, metaKey, RollupState.GenericInfo.class);
    info.value = value;

    calc.setState(outerState);
    calc.setFullRecalc(true);
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount = 0', Opportunity.SObjectType));

    Opportunity one = new Opportunity(Id = '0066g00003VDGbF001', Amount = 5, AccountId = accountKey);
    Opportunity two = new Opportunity(Id = '0066g00003VDGbF002', Amount = 5, AccountId = accountKey);

    calc.performRollup(new List<Opportunity>{ one, two }, new Map<Id, SObject>());

    System.assertEquals(value, calc.getReturnValue());
    System.assertEquals(value, info.value);
  }

  // CONCAT tests

  @IsTest
  static void shouldReturnDefaultIfNoMatchingItemsPassedConcat() {
    String distinct = 'distinct';
    RollupCalculator calc = getCalculator(
      distinct,
      Rollup.Op.CONCAT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = distinct, AccountId = '0016g00003VDGbF001');
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Name != ' + opp.Name, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void shouldDistinctByFlagForConcat() {
    String distinct = 'distinct';
    Object parentStartingValue = '';
    Id stubParentId = RollupTestUtils.createId(Schema.Account.SObjectType);
    RollupCalculator calc = getCalculator(
      parentStartingValue,
      Rollup.Op.CONCAT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(IsDistinct__c = true),
      stubParentId,
      Opportunity.AccountId
    );

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = RollupTestUtils.createId(Schema.Opportunity.SObjectType), Name = distinct, AccountId = stubParentId),
        new Opportunity(Id = RollupTestUtils.createId(Schema.Opportunity.SObjectType), Name = distinct, AccountId = stubParentId)
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(distinct, calc.getReturnValue());
  }

  @IsTest
  static void shouldProperlyRemoveConcatOnUpdateIfOldItemMatchesAndNewOneDoesNot() {
    Opportunity opp = new Opportunity(AccountId = '0011g00003VDGbF002', Id = '0066g00003VDGbF001', Name = 'CDC', Amount = 0);

    RollupCalculator calc = getCalculator(
      'GISS, CDC',
      Rollup.Op.UPDATE_CONCAT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));
    Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Amount = 5, Name = 'CDC') };

    calc.performRollup(new List<Opportunity>{ opp }, oldOppMap);

    System.assertEquals('GISS', calc.getReturnValue());
  }

  @IsTest
  static void shouldConcatDistinctProperly() {
    String distinct = 'distinct';
    RollupCalculator calc = getCalculator(
      distinct,
      Rollup.Op.CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = distinct, AccountId = '0016g00003VDGbF001');
    Opportunity nonDistinctOpp = new Opportunity(Id = '0066g00003VDGbF002', Name = 'non' + distinct, AccountId = '0016g00003VDGbF001');
    calc.performRollup(new List<Opportunity>{ opp, nonDistinctOpp }, new Map<Id, SObject>());

    System.assertEquals(
      distinct + ', ' + nonDistinctOpp.Name,
      (String) calc.getReturnValue(),
      'Value containing original distinct value should also be concatenated'
    );
  }

  @IsTest
  static void shouldRemoveOldValueForConcatDistinctUpdate() {
    String accountId = '0016g00003VDGbF001';
    String firstVal = '2011';
    String secondVal = '2021';
    RollupCalculator calc = getCalculator(
      firstVal + ', ' + secondVal,
      Rollup.Op.UPDATE_CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(),
      accountId,
      Opportunity.AccountId
    );

    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = secondVal, AccountId = accountId);
    Opportunity oldOpp = new Opportunity(Id = '0066g00003VDGbF001', Name = firstVal, AccountId = accountId);
    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>{ oldOpp.Id => oldOpp });

    System.assertEquals(secondVal, calc.getReturnValue(), 'Old value should be removed');
  }

  @IsTest
  static void shouldUseCustomConcatDelimiterWhenSupplied() {
    String distinct = 'distinct';
    RollupCalculator calc = getCalculator(
      distinct,
      Rollup.Op.CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(ConcatDelimiter__c = ' -- '),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = distinct, AccountId = '0016g00003VDGbF001');
    Opportunity nonDistinctOpp = new Opportunity(Id = '0066g00003VDGbF001', Name = 'non' + distinct, AccountId = '0016g00003VDGbF001');
    calc.performRollup(new List<Opportunity>{ opp, nonDistinctOpp }, new Map<Id, SObject>());

    System.assertEquals(distinct + ' -- ' + nonDistinctOpp.Name, calc.getReturnValue(), 'distinct values should be concatenated with custom delimiter!');
  }

  @IsTest
  static void shouldProperlyAccountForPreExistingValueWitNewLineDelimiter() {
    String distinct = 'distinct';
    RollupCalculator calc = getCalculator(
      distinct,
      Rollup.Op.CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(ConcatDelimiter__c = '\\n'),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = distinct, AccountId = '0016g00003VDGbF001');
    Opportunity nonDistinctOpp = new Opportunity(Id = '0066g00003VDGbF001', Name = 'non' + distinct, AccountId = '0016g00003VDGbF001');
    calc.performRollup(new List<Opportunity>{ opp, nonDistinctOpp }, new Map<Id, SObject>());

    System.assertEquals(distinct + '\n' + nonDistinctOpp.Name, String.valueOf(calc.getReturnValue()).trim());
  }

  @IsTest
  static void shouldSplitCalcItemsOnConcatDelimiterWhenSupplied() {
    RollupCalculator calc = getCalculator(
      '',
      Rollup.Op.CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(SplitConcatDelimiterOnCalcItem__c = true),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = '2017, 2018, 2019', AccountId = '0016g00003VDGbF001');
    Opportunity secondOpp = new Opportunity(Id = '0066g00003VDGbF001', Name = '2019, 2020, 2021', AccountId = '0016g00003VDGbF001');
    calc.performRollup(new List<Opportunity>{ opp, secondOpp }, new Map<Id, SObject>());

    System.assertEquals('2017, 2018, 2019, 2020, 2021', calc.getReturnValue());
  }

  @IsTest
  static void shouldNotSplitOnConcatDelimiterWhenOnlyBlankValueStillExists() {
    RollupCalculator calc = getCalculator(
      '2019, 2020, 2021',
      Rollup.Op.DELETE_CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(SplitConcatDelimiterOnCalcItem__c = true),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = '2019, 2020, 2021', AccountId = '0016g00003VDGbF001');
    Opportunity secondOpp = new Opportunity(Id = '0066g00003VDGbF001', Name = '2019, 2020, 2021', AccountId = '0016g00003VDGbF001');
    calc.performRollup(new List<Opportunity>{ opp, secondOpp }, new Map<Id, SObject>());

    System.assertEquals('', calc.getReturnValue());
  }

  @IsTest
  static void shouldProperlyRemoveConcatDistinctOnUpdateIfOldItemMatchesAndNewOneDoesNot() {
    Account acc = [SELECT Id FROM Account];
    String toRemove = 'CDC';
    String extantString = 'GISS';
    insert new Opportunity(Name = extantString, CloseDate = System.today(), StageName = 'A', AccountId = acc.Id);
    RollupCalculator calc = getCalculator(
      toRemove + ', ' + extantString,
      Rollup.Op.UPDATE_CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(),
      acc.Id,
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));
    Opportunity opp = new Opportunity(Amount = 0, Id = '0066g00003VDGbF001', Name = 'CDC', AccountId = acc.Id);
    Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Amount = 5, Name = 'CDC') };

    calc.performRollup(new List<Opportunity>{ opp }, oldOppMap);

    System.assertEquals('GISS', calc.getReturnValue());
  }

  @IsTest
  static void shouldNotRemoveValuesOnConcatDistinctDeleteIfItemDoesNotMatch() {
    Account acc = [SELECT Id FROM Account];

    insert new Opportunity(AccountId = acc.Id, StageName = 'hi', CloseDate = System.today(), Name = 'Delete');

    RollupCalculator calc = getCalculator(
      'CDC, Delete',
      Rollup.Op.DELETE_CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(),
      acc.Id,
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity opp = new Opportunity(Amount = 0, Id = '0066g00003VDGbF001', Name = 'CDC', AccountId = acc.Id);

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, Opportunity>());

    System.assertEquals('Delete', calc.getReturnValue());
  }

  @IsTest
  static void regressionShouldNotBlowUpOnNullPriorValueConcat() {
    RollupCalculator calc = getCalculator(
      '',
      Rollup.Op.UPDATE_CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = null, AccountId = '0016g00003VDGbF001');
    Opportunity nonDistinctOpp = new Opportunity(Id = '0066g00003VDGbF001', Name = 'non', AccountId = '0016g00003VDGbF001');
    calc.performRollup(new List<Opportunity>{ opp, nonDistinctOpp }, new Map<Id, SObject>{ opp.Id => opp });

    System.assertEquals(nonDistinctOpp.Name, (String) calc.getReturnValue(), 'should not blow up on null!');
  }

  // PICKLIST tests

  @IsTest
  static void shouldConcatenateProperlyToMultiSelectPicklist() {
    RollupCalculator calc = getCalculator(
      '',
      Rollup.Op.CONCAT,
      Opportunity.Name,
      QuickText.Channel,
      new Rollup__mdt(),
      RollupTestUtils.createId(QuickText.SObjectType),
      QuickText.Name
    );

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Name = 'Hello'),
        new Opportunity(Name = 'World, I know'),
        new Opportunity(Name = 'And'),
        new Opportunity(Name = 'SSK')
      },
      new Map<Id, SObject>()
    );

    System.assertEquals('And;Hello;SSK;World, I know', (String) calc.getReturnValue(), 'Multi-select should use ; to concat');
  }

  @IsTest
  static void shouldMinOnMultiSelectPicklist() {
    Rollup__mdt metadata = new Rollup__mdt();
    RollupCalculator calc = getCalculator(
      '',
      Rollup.Op.MIN,
      QuickText.Channel,
      Opportunity.Name,
      metadata,
      RollupTestUtils.createId(Opportunity.SObjectType),
      QuickText.Name
    );

    List<Schema.PicklistEntry> picklistVals = QuickText.Channel.getDescribe().getPicklistValues();
    if (picklistVals.size() < 3) {
      return;
    }

    String firstVal = picklistVals[0].getValue();
    String secondVal = picklistVals[1].getValue();
    String thirdVal = picklistVals[2].getValue();

    calc.performRollup(
      new List<QuickText>{ new QuickText(Channel = firstVal + ';' + secondVal), new QuickText(Channel = secondVal + ';' + thirdVal) },
      new Map<Id, SObject>()
    );

    System.assertEquals(firstVal + ';' + secondVal, calc.getReturnValue(), 'Min should take first entries for multi-select picklists');
  }

  @IsTest
  static void concatDistinctOnMultiSelectPicklistSortsProperly() {
    List<Schema.PicklistEntry> picklistVals = QuickText.Channel.getDescribe().getPicklistValues();
    if (picklistVals.size() < 3) {
      return;
    }

    String firstVal = picklistVals[0].getValue();
    String secondVal = picklistVals[1].getValue();
    String thirdVal = picklistVals[2].getValue();

    RollupCalculator calc = getCalculator(
      firstVal,
      Rollup.Op.CONCAT_DISTINCT,
      QuickText.Channel,
      QuickText.Channel,
      new Rollup__mdt(),
      RollupTestUtils.createId(Opportunity.SObjectType),
      QuickText.Name
    );

    calc.performRollup(
      new List<QuickText>{
        new QuickText(Channel = firstVal + ';' + secondVal),
        new QuickText(Channel = secondVal + ';' + thirdVal),
        new QuickText(Channel = thirdVal + ';' + firstVal)
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(firstVal + ';' + secondVal + ';' + thirdVal, calc.getReturnValue(), 'Concat distinct works properly for MSP');
  }

  @IsTest
  static void concatDistinctOnMSPDoesNotIncludeFirstValueWhenNotPartOfChildren() {
    List<Schema.PicklistEntry> picklistVals = QuickText.Channel.getDescribe().getPicklistValues();
    if (picklistVals.size() < 3) {
      return;
    }

    String firstVal = picklistVals[0].getValue();
    String secondVal = picklistVals[1].getValue();
    String thirdVal = picklistVals[2].getValue();

    RollupCalculator calc = getCalculator(
      firstVal,
      Rollup.Op.CONCAT_DISTINCT,
      QuickText.Channel,
      QuickText.Channel,
      new Rollup__mdt(),
      RollupTestUtils.createId(Opportunity.SObjectType),
      QuickText.Name
    );

    calc.performRollup(
      new List<QuickText>{
        new QuickText(Channel = secondVal),
        new QuickText(Channel = secondVal + ';' + thirdVal),
        new QuickText(Channel = thirdVal + ';' + secondVal)
      },
      new Map<Id, SObject>()
    );

    String returnVal = String.valueOf(calc.getReturnValue());
    System.assertEquals(false, returnVal.contains(firstVal), returnVal + ' should not have included: ' + firstVal);
    System.assertEquals(secondVal + ';' + thirdVal, returnVal, 'Concat distinct does not include first value');
  }

  @IsTest
  static void concatOnMSPDoesNotIncludeFirstValueWhenNotPartOfChildren() {
    List<Schema.PicklistEntry> picklistVals = QuickText.Channel.getDescribe().getPicklistValues();
    if (picklistVals.size() < 3) {
      return;
    }

    String firstVal = picklistVals[0].getValue();
    String secondVal = picklistVals[1].getValue();
    String thirdVal = picklistVals[2].getValue();

    RollupCalculator calc = getCalculator(
      firstVal,
      Rollup.Op.CONCAT,
      QuickText.Channel,
      QuickText.Channel,
      new Rollup__mdt(),
      RollupTestUtils.createId(Opportunity.SObjectType),
      QuickText.Name
    );

    calc.performRollup(
      new List<QuickText>{
        new QuickText(Channel = secondVal),
        new QuickText(Channel = secondVal + ';' + thirdVal),
        new QuickText(Channel = thirdVal + ';' + secondVal)
      },
      new Map<Id, SObject>()
    );

    String returnVal = String.valueOf(calc.getReturnValue());
    System.assertEquals(false, returnVal.contains(firstVal), returnVal + ' should not have included: ' + firstVal);
    System.assertEquals(secondVal.repeat(';', 3) + ';' + thirdVal.repeat(';', 2), returnVal, 'Concat distinct does not include first value');
  }

  // MIN / MAX

  @IsTest
  static void supportsMaxFromPicklists() {
    RollupCalculator calc = getCalculator(
      '',
      Rollup.Op.MAX,
      ContactPointAddress.Name,
      Account.Industry,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Account.Id
    );

    Assert.isNotNull(calc);
  }

  @IsTest
  static void shouldDefaultToNullIfCurrentItemExcludedAndNoOtherMatchingItemsTime() {
    Time max = Time.newInstance(11, 11, 11, 11);
    Rollup__mdt metadata = new Rollup__mdt(CalcItem__c = 'ContactPointAddress', CalcItemWhereClause__c = 'BestTimeToContactEndTime != ' + String.valueOf(max));
    RollupCalculator calc = getCalculator(
      max,
      Rollup.Op.UPDATE_MIN,
      ContactPointAddress.BestTimeToContactEndTime,
      ContactPointAddress.BestTimeToContactEndTime,
      metadata,
      RollupTestUtils.createId(ContactPointAddress.SObjectType),
      ContactPointAddress.Id
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator(metadata.CalcItemWhereClause__c, ContactPointAddress.SObjectType));

    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = max, Name = 'Min time');

    calc.performRollup(
      new List<ContactPointAddress>{ cpa },
      new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12)) }
    );

    System.assertEquals(null, calc.getReturnValue(), 'Should be nulled out if no matching minimum');
  }

  @IsTest
  static void respectsDefaultFullRecalcValueMinMaxInsteadOfNull() {
    Rollup__mdt metadata = new Rollup__mdt(FullRecalculationDefaultNumberValue__c = 5, CalcItem__c = 'Task');
    RollupCalculator calc = getCalculator(
      2,
      Rollup.Op.MIN,
      Task.CallDurationInSeconds,
      Opportunity.Amount,
      metadata,
      RollupTestUtils.createId(Opportunity.SObjectType),
      Task.WhatId
    );

    calc.performRollup(new List<Task>(), new Map<Id, SObject>());

    System.assertEquals(metadata.FullRecalculationDefaultNumberValue__c, calc.getReturnValue(), 'Should correctly find minimum');
  }

  @IsTest
  static void shouldDefaultToCurrentValueOnMinIfNoOtherMatchingItemsDate() {
    Rollup__mdt metadata = new Rollup__mdt();
    Date today = System.today();
    RollupCalculator calc = getCalculator(
      today,
      Rollup.Op.UPDATE_MIN,
      Task.ActivityDate, // not a "MIN"-able field in SOQL; crucial for this test
      Opportunity.CloseDate,
      metadata,
      RollupTestUtils.createId(Opportunity.SObjectType),
      Task.WhatId
    );

    // the important things here: the current date is greater than both the passed in date (the "current" value on the parent object)
    // AND that the "current" value matches what's on the old item
    Task t = new Task(ActivityDate = today.addDays(1), Id = RollupTestUtils.createId(Task.SObjectType));

    calc.performRollup(new List<Task>{ t }, new Map<Id, SObject>{ t.Id => new Task(ActivityDate = today) });

    System.assertEquals(t.ActivityDate, calc.getReturnValue(), 'Should correctly find minimum');
  }

  @IsTest
  static void dateMinDoesNotBlowUpOnNullValue() {
    Date firstPossibleDate = Date.newInstance(1970, 1, 1);
    RollupCalculator calc = getCalculator(
      firstPossibleDate,
      Rollup.Op.MIN,
      Opportunity.CloseDate, // not a "MIN"-able field in SOQL; crucial for this test
      Opportunity.CloseDate,
      new Rollup__mdt(),
      RollupTestUtils.createId(Opportunity.SObjectType),
      Opportunity.Name
    );

    calc.performRollup(new List<SObject>(), new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void shouldDefaultToCurrentValueOnMinIfNoOtherMatchingItemsTime() {
    Rollup__mdt metadata = new Rollup__mdt();
    Time max = Time.newInstance(11, 11, 11, 11);
    RollupCalculator calc = getCalculator(
      max,
      Rollup.Op.UPDATE_MIN,
      ContactPointAddress.BestTimeToContactEndTime,
      ContactPointAddress.BestTimeToContactEndTime,
      metadata,
      RollupTestUtils.createId(ContactPointAddress.SObjectType),
      ContactPointAddress.Id
    );

    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12), Name = 'Min time');

    calc.performRollup(new List<ContactPointAddress>{ cpa }, new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(BestTimeToContactEndTime = max) });

    System.assertEquals(cpa.BestTimeToContactEndTime, calc.getReturnValue(), 'Should be nulled out if no matching minimum');
  }

  @IsTest
  static void shouldCorrectlyUpdateMinIfOnlyMatchingItemChanges() {
    Rollup__mdt metadata = new Rollup__mdt();
    Time max = Time.newInstance(11, 11, 11, 11);
    RollupCalculator calc = getCalculator(
      max,
      Rollup.Op.UPDATE_MIN,
      ContactPointAddress.BestTimeToContactEndTime,
      ContactPointAddress.BestTimeToContactEndTime,
      metadata,
      RollupTestUtils.createId(ContactPointAddress.SObjectType),
      ContactPointAddress.Id
    );

    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(12, 12, 12, 12), Name = 'Min time');
    insert cpa;

    calc.performRollup(new List<ContactPointAddress>{ cpa }, new Map<Id, SObject>{ cpa.Id => new ContactPointAddress(BestTimeToContactEndTime = max) });

    System.assertEquals(cpa.BestTimeToContactEndTime, calc.getReturnValue(), 'Should correctly return min if only one matching item');
  }

  @IsTest
  static void shouldDefaultToCurrentValueOnMaxIfNoOtherMatchingItemsDate() {
    Rollup__mdt metadata = new Rollup__mdt();
    Date today = System.today();
    RollupCalculator calc = getCalculator(
      today,
      Rollup.Op.UPDATE_MAX,
      Task.ActivityDate, // not a "MAX"-able field in SOQL; crucial for this test
      Opportunity.CloseDate,
      metadata,
      RollupTestUtils.createId(Opportunity.SObjectType),
      Task.WhatId
    );

    // the important things here: the current date is less than both the passed in date (the "current" value on the parent object)
    // AND that the "current" value matches what's on the old item
    Task t = new Task(ActivityDate = today.addDays(-1), Id = RollupTestUtils.createId(Task.SObjectType));

    calc.performRollup(new List<Task>{ t }, new Map<Id, SObject>{ t.Id => new Task(ActivityDate = today) });

    System.assertEquals(t.ActivityDate, calc.getReturnValue(), 'Should be nulled out if no matching maximum');
  }

  @IsTest
  static void shouldProperlyUpdateMinOnUpdateIfOldItemMatchesAndNewOneDoesNot() {
    Account acc = [SELECT Id FROM Account];
    Opportunity opp = new Opportunity(AccountId = acc.Id, CloseDate = System.today(), StageName = 'Hi', Name = 'Count Distinct', Amount = 5);
    Opportunity newMin = opp.clone();
    newMin.Amount = 3;
    insert new List<Opportunity>{ opp, newMin };

    Opportunity newerOpp = opp.clone(true, true);
    newerOpp.Amount = 0;

    RollupCalculator calc = getCalculator(5, Rollup.Op.UPDATE_MIN, Opportunity.Amount, Account.AnnualRevenue, new Rollup__mdt(), acc.Id, Opportunity.AccountId);
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));
    Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>{ opp.Id => opp };

    calc.performRollup(new List<Opportunity>{ newerOpp }, oldOppMap);

    System.assertEquals(3, calc.getReturnValue());
  }

  @IsTest
  static void shouldProperlyUpdateMaxOnUpdateIfOldItemMatchesAndNewOneDoesNot() {
    Account acc = [SELECT Id FROM Account];
    Opportunity opp = new Opportunity(AccountId = acc.Id, CloseDate = System.today(), StageName = 'Hi', Name = 'Count Distinct', Amount = 5);
    Opportunity newMax = opp.clone();
    newMax.Amount = 7;
    insert new List<Opportunity>{ opp, newMax };

    Opportunity newerOpp = opp.clone(true, true);
    newerOpp.Amount = 0;

    RollupCalculator calc = getCalculator(5, Rollup.Op.UPDATE_MAX, Opportunity.Amount, Account.AnnualRevenue, new Rollup__mdt(), acc.Id, Opportunity.AccountId);
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));
    Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>{ opp.Id => opp };

    calc.performRollup(new List<Opportunity>{ newerOpp }, oldOppMap);

    System.assertEquals(7, calc.getReturnValue());
  }

  // Base recalculation tests

  @IsTest
  static void shouldNotThrowExceptionWhenFilteringOnUnfilterableFields() {
    Account acc = [SELECT Id FROM Account];
    Case cas = new Case(AccountId = acc.Id, Description = 'Something', Subject = 'Hello');
    insert cas;

    Rollup__mdt meta = new Rollup__mdt(CalcItem__c = 'Case', LookupObject__c = 'Account', CalcItemWhereClause__c = 'Description != \'Something\'');
    RollupCalculator calc = getCalculator('', Rollup.Op.CONCAT_DISTINCT, Case.Description, Account.Description, meta, acc.Id, Account.Id);
    calc.setEvaluator(RollupEvaluator.getWhereEval(meta.CalcItemWhereClause__c, Case.SObjectType));
    calc.performRollup(new List<Case>{ cas }, new Map<Id, Case>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void properlyConvertsDownstreamTypesToDecimals() {
    RollupCalculator calc = getCalculator(
      System.today().addDays(-10),
      Rollup.Op.MAX,
      Opportunity.CloseDate,
      Contact.BirthDate,
      new Rollup__mdt(),
      RollupTestUtils.createId(Contact.SObjectType),
      Opportunity.Name
    );

    Object newDefaultValue = System.today();
    calc.setDefaultValues(RollupTestUtils.createId(Contact.SObjectType), newDefaultValue);

    System.assertEquals(newDefaultValue, calc.getReturnValue());

    newDefaultValue = System.now();
    calc = getCalculator(
      newDefaultValue,
      Rollup.Op.MAX,
      Opportunity.CloseDate,
      Event.ActivityDatetime,
      new Rollup__mdt(),
      RollupTestUtils.createId(Contact.SObjectType),
      Opportunity.Name
    );

    System.assertEquals(newDefaultValue, calc.getReturnValue());

    newDefaultValue = Time.newInstance(1, 0, 0, 0);
    calc = getCalculator(
      newDefaultValue,
      Rollup.Op.MAX,
      Opportunity.CloseDate,
      ContactPointAddress.BestTimeToContactStartTime,
      new Rollup__mdt(),
      RollupTestUtils.createId(Contact.SObjectType),
      Opportunity.Name
    );
    calc.setDefaultValues(RollupTestUtils.createId(Contact.SObjectType), newDefaultValue);

    System.assertEquals(newDefaultValue, calc.getReturnValue());
  }

  // Factory tests

  @IsTest
  static void shouldNotMixReturnTypesWithBigDecimalUnsortableValues() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.MAX,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );

    Opportunity badAmountOpp = new Opportunity(Amount = RollupFieldInitializer.Current.maximumLongValue);
    calc.performRollup(new List<SObject>{ badAmountOpp }, new Map<Id, SObject>());

    Account accountWithBadRevenue = new Account();
    accountWithBadRevenue.put(Account.AnnualRevenue, calc.getReturnValue());
    Account accountWithDecimalRevenue = new Account(AnnualRevenue = 15.154);

    // normally, I'd wrap this in a try/catch block, but the error that gets thrown is uncatchable
    new List<Account>{ accountWithBadRevenue, accountWithDecimalRevenue }.sort();

    System.assert(true, 'Made it here!');
  }

  @IsTest
  static void shouldRecalcCountDistinctWithoutBigDecimalUnsortableIssue() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.DELETE_COUNT_DISTINCT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );

    Opportunity badAmountOpp = new Opportunity(Amount = 0);
    calc.performRollup(new List<SObject>{ badAmountOpp }, new Map<Id, SObject>());

    Account accountWithBadRevenue = new Account();
    accountWithBadRevenue.put(Account.AnnualRevenue, calc.getReturnValue());
    Account accountWithDecimalRevenue = new Account(AnnualRevenue = 15.154);

    // normally, I'd wrap this in a try/catch block, but the error that gets thrown is uncatchable
    new List<Account>{ accountWithBadRevenue, accountWithDecimalRevenue }.sort();

    System.assert(true, 'Made it here!');
  }

  @IsTest
  static void shouldRecalcCountWithoutBigDecimalUnsortableIssue() {
    RollupCalculator calc = getCalculator(
      0.00,
      Rollup.Op.COUNT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );

    Opportunity badAmountOpp = new Opportunity(Amount = 0);
    calc.performRollup(new List<SObject>{ badAmountOpp }, new Map<Id, SObject>());

    Account accountWithBadRevenue = new Account();
    accountWithBadRevenue.put(Account.AnnualRevenue, calc.getReturnValue());
    Account accountWithDecimalRevenue = new Account(AnnualRevenue = 15.154);

    // normally, I'd wrap this in a try/catch block, but the error that gets thrown is uncatchable
    new List<Account>{ accountWithBadRevenue, accountWithDecimalRevenue }.sort();

    System.assert(true, 'Made it here!');
  }

  @IsTest
  static void shouldRecalcCountUpdateWithoutBigDecimalUnsortableIssue() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.UPDATE_COUNT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );

    Opportunity badAmountOpp = new Opportunity(Id = RollupTestUtils.createId(Opportunity.SObjectType));
    calc.performRollup(new List<SObject>{ badAmountOpp }, new Map<Id, SObject>{ badAmountOpp.Id => new Opportunity(Amount = 15) });

    Account accountWithBadRevenue = new Account();
    accountWithBadRevenue.put(Account.AnnualRevenue, calc.getReturnValue());
    Account accountWithDecimalRevenue = new Account(AnnualRevenue = 15.154);

    // normally, I'd wrap this in a try/catch block, but the error that gets thrown is uncatchable
    new List<Account>{ accountWithBadRevenue, accountWithDecimalRevenue }.sort();

    System.assert(true, 'Made it here!');
  }

  @IsTest
  static void shouldRecalcNullsWithoutBigDecimalUnsortableIssue() {
    Integer oldMax = 2;
    RollupCalculator calc = getCalculator(
      oldMax,
      Rollup.Op.UPDATE_MAX,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );

    // need the old amount to be equal to the max; new amount to be less than max
    // then have a second item which is less than the old max but greater than the new amount on the first item
    Opportunity oldMaxOpp = new Opportunity(Amount = -1, Id = RollupTestUtils.createId(Opportunity.SObjectType));
    Opportunity newMaxOpp = new Opportunity(Amount = null, Id = RollupTestUtils.createId(Opportunity.SObjectType));
    calc.performRollup(
      new List<SObject>{ oldMaxOpp, newMaxOpp },
      new Map<Id, SObject>{
        oldMaxOpp.Id => new Opportunity(Id = oldMaxOpp.Id, Amount = oldMax),
        newMaxOpp.Id => new Opportunity(Id = newMaxOpp.Id, Amount = 0)
      }
    );

    Account accountWithBadRevenue = new Account();
    accountWithBadRevenue.put(Account.AnnualRevenue, calc.getReturnValue());
    Account accountWithDecimalRevenue = new Account(AnnualRevenue = 15.154);

    // normally, I'd wrap this in a try/catch block, but the error that gets thrown is uncatchable
    new List<Account>{ accountWithBadRevenue, accountWithDecimalRevenue }.sort();

    System.assert(true, 'Made it here!');
  }

  @IsTest
  static void shouldSetDecimalsWithoutBigDecimalUnsortableIssue() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.MAX,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );

    Opportunity oppOne = new Opportunity(Amount = 1);
    Opportunity oppTwo = new Opportunity(Amount = 2);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());
    Account accountWithBadRevenue = new Account();
    accountWithBadRevenue.put(Account.AnnualRevenue, calc.getReturnValue());
    Account accountWithDecimalRevenue = new Account(AnnualRevenue = 15.154);

    // normally, I'd wrap this in a try/catch block, but the error that gets thrown is uncatchable
    new List<Account>{ accountWithBadRevenue, accountWithDecimalRevenue }.sort();

    System.assert(true, 'Made it here!');
  }

  // ALL

  @IsTest
  static void allUsesFullRecalcDefaultValueWhenNotMatching() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.ALL,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(FullRecalculationDefaultNumberValue__c = 5),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 1', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 1);
    Opportunity oppTwo = new Opportunity(Amount = 1);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(5, calc.getReturnValue());
  }

  @IsTest
  static void allReportsPositivesCorrectlyAsNumber() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.ALL,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 1);
    Opportunity oppTwo = new Opportunity(Amount = 1);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(1, calc.getReturnValue());
  }

  @IsTest
  static void allReportsPositivesCorrectlyAsBoolean() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.ALL,
      Opportunity.Amount,
      User.IsActive,
      new Rollup__mdt(),
      RollupTestUtils.createId(User.SObjectType),
      Opportunity.OwnerId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 1);
    Opportunity oppTwo = new Opportunity(Amount = 1);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(true, calc.getReturnValue());
  }

  @IsTest
  static void allReportsPositivesCorrectlyAsString() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.ALL,
      Opportunity.Amount,
      Account.Description,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 1);
    Opportunity oppTwo = new Opportunity(Amount = 1);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(String.valueOf(true), calc.getReturnValue());
  }

  @IsTest
  static void allReportsNegativesCorrectlyAsNumber() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.ALL,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 1);
    Opportunity oppTwo = new Opportunity(Amount = 0);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(0, calc.getReturnValue());
  }

  @IsTest
  static void allReportsNegativesCorrectlyAsBoolean() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.ALL,
      Opportunity.Amount,
      User.IsActive,
      new Rollup__mdt(),
      RollupTestUtils.createId(User.SObjectType),
      Opportunity.OwnerId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 1);
    Opportunity oppTwo = new Opportunity(Amount = 0);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(false, calc.getReturnValue());
  }

  @IsTest
  static void allReportsNegativesCorrectlyAsString() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.ALL,
      Opportunity.Amount,
      Account.Description,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 1);
    Opportunity oppTwo = new Opportunity(Amount = 0);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(String.valueOf(false), calc.getReturnValue());
  }

  // SOME

  @IsTest
  static void someReportsPositivesCorrectlyAsNumber() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.SOME,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 1);
    Opportunity oppTwo = new Opportunity(Amount = 0);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(1, calc.getReturnValue());
  }

  @IsTest
  static void someReportsNegativesCorrectlyAsNumber() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.SOME,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 0);
    Opportunity oppTwo = new Opportunity(Amount = 0);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(0, calc.getReturnValue());
  }

  @IsTest
  static void correctlyFlipsSomeToFalsyOnNonMatchingUpdate() {
    RollupCalculator calc = getCalculator(
      1,
      Rollup.Op.SOME,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Id = RollupTestUtils.createId(Opportunity.SObjectTYpe), Amount = 0);
    Opportunity oldOppOne = oppOne.clone(true);
    oldOppOne.Amount = 1;
    Opportunity oppTwo = new Opportunity(Id = RollupTestUtils.createId(Opportunity.SObjectTYpe), Amount = 0);
    Opportunity oldOppTwo = oppTwo.clone(true);
    oldOppTwo.Amount = 1;

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>{ oppOne.Id => oldOppOne, oppTwo.Id => oldOppTwo });

    System.assertEquals(0, calc.getReturnValue());
  }

  // NONE

  @IsTest
  static void noneReportsPositivesCorrectlyAsNumber() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.NONE,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 0);
    Opportunity oppTwo = new Opportunity(Amount = 0);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(1, calc.getReturnValue());
  }

  @IsTest
  static void noneReportsNegativesCorrectlyAsNumber() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.NONE,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      RollupTestUtils.createId(Account.SObjectType),
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));

    Opportunity oppOne = new Opportunity(Amount = 1);
    Opportunity oppTwo = new Opportunity(Amount = 0);

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    System.assertEquals(0, calc.getReturnValue());
  }

  @IsTest
  static void shouldInvokeNoOpMethodsWithoutFail() {
    RollupCalculator calc = new RollupCalcEmptyMock();
    calc.handleCountDistinct(null);
    calc.handleUpdateCountDistinct(null);
    calc.handleSumOrCount(null);
    calc.handleUpdateSumOrCount(null);
    calc.handleDeleteSumOrCount(null);
    calc.handleMin(null);
    calc.handleMax(null);
    calc.handleUpdateMinOrMax(null);
    calc.handleConcat(null);
    calc.handleUpdateConcat(null);
    calc.handleDeleteConcat(null);

    System.assert(true, 'Should make it here');
  }

  @IsTest
  static void convertsDatesProperly() {
    RollupCalculator calc = getCalculator(
      null,
      Rollup.Op.MIN,
      Opportunity.Description,
      Opportunity.CloseDate,
      new Rollup__mdt(CalcItem__c = String.valueOf(Opportunity.SObjectType)),
      RollupTestUtils.createId(Opportunity.SObjectType),
      Opportunity.Id
    );

    Opportunity oppOne = new Opportunity(Description = '2020-01-01');
    Opportunity oppTwo = new Opportunity(Description = '2020-01-02');

    calc.performRollup(new List<SObject>{ oppOne, oppTwo }, new Map<Id, SObject>());

    Assert.isInstanceOfType(calc.getReturnValue(), Date.class, 'Should have been properly converted');
    System.assertEquals(Date.valueOf(oppOne.Description), calc.getReturnValue());
  }

  @IsTest
  static void performsGroupByWhenSupplied() {
    String rowEndDelimiter = '\n\t';
    String rowStartDelimiter = '* ';
    RollupCalculator calc = getCalculator(
      null,
      Rollup.Op.SUM,
      Opportunity.Amount,
      Account.Description,
      new Rollup__mdt(
        CalcItem__c = String.valueOf(Opportunity.SObjectType),
        GroupByFields__c = 'StageName, Name',
        GroupByRowEndDelimiter__c = rowEndDelimiter,
        GroupByRowStartDelimiter__c = rowStartDelimiter
      ),
      RollupTestUtils.createId(Account.SObjectType),
      Account.Id
    );

    calc.performRollup(
      new List<SObject>{
        new Opportunity(StageName = 'Two', Name = 'Deux', Amount = 50),
        new Opportunity(StageName = 'Z', Name = 'A', Amount = 50),
        new Opportunity(StageName = 'Two', Name = 'Deux', Amount = 50),
        new Opportunity(Amount = 50),
        new Opportunity(StageName = 'Z', Amount = 50),
        new Opportunity(StageName = 'One', Amount = 50),
        new Opportunity(StageName = 'One', Amount = 50)
      },
      new Map<Id, SObject>()
    );

    String expectedGroupByString =
      rowStartDelimiter +
      '(blank), (blank), 50.0' +
      rowEndDelimiter +
      rowStartDelimiter +
      'One, (blank), 100.0' +
      rowEndDelimiter +
      rowStartDelimiter +
      'Two, Deux, 100.0' +
      rowEndDelimiter +
      rowStartDelimiter +
      'Z, (blank), 50.0' +
      rowEndDelimiter +
      rowStartDelimiter +
      'Z, A, 50.0';
    System.assertEquals(expectedGroupByString, calc.getReturnValue());
  }

  @IsTest
  static void respectsCustomConcatDelimiterForGroupBy() {
    RollupCalculator calc = getCalculator(
      null,
      Rollup.Op.SUM,
      Opportunity.Amount,
      Account.Description,
      new Rollup__mdt(CalcItem__c = String.valueOf(Opportunity.SObjectType), GroupByFields__c = 'StageName, Name', ConcatDelimiter__c = '; '),
      RollupTestUtils.createId(Account.SObjectType),
      Account.Id
    );

    calc.performRollup(
      new List<SObject>{
        new Opportunity(StageName = 'Two', Name = 'Deux', Amount = 50),
        new Opportunity(StageName = 'Two', Name = 'Deux', Amount = 50),
        new Opportunity(StageName = 'One', Amount = 50),
        new Opportunity(StageName = 'One', Amount = 50)
      },
      new Map<Id, SObject>()
    );

    System.assertEquals('• One; (blank); 100.0\n• Two; Deux; 100.0', calc.getReturnValue());
  }

  @IsTest
  static void doesNotConvertCurrencyWhenGroupingByCurrencyIsoCode() {
    if (RollupCurrencyInfo.IS_MULTICURRENCY == false) {
      return;
    }
    Account fakeAccount = new Account(Id = RollupTestUtils.createId(Account.SObjectType));
    fakeAccount.put(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME, 'USD');

    RollupCalculator calc = getCalculator(
      null,
      Rollup.Op.SUM,
      Opportunity.Amount,
      Account.Description,
      new Rollup__mdt(
        CalcItem__c = String.valueOf(Opportunity.SObjectType),
        CurrencyFieldMapping__c = 'CloseDate',
        GroupByFields__c = 'StageName, CurrencyIsoCode'
      ),
      fakeAccount.Id,
      Account.Id
    );
    calc.setMultiCurrencyInfo(fakeAccount);

    List<SObject> opportunities = new List<SObject>{
      new Opportunity(StageName = 'One', Amount = 50),
      new Opportunity(StageName = 'One', Amount = 50),
      new Opportunity(StageName = 'One', Amount = 50),
      new Opportunity(StageName = 'One', Amount = 50)
    };
    for (Integer index = 0; index < opportunities.size(); index++) {
      opportunities[index].put(RollupCurrencyInfo.CURRENCY_ISO_CODE_FIELD_NAME, Math.mod(index, 2) == 0 ? 'EUR' : 'JPY');
    }

    calc.performRollup(opportunities, new Map<Id, SObject>());

    System.assertEquals('• One, EUR, 100.0\n• One, JPY, 100.0', calc.getReturnValue());
  }

  @IsTest
  static void displaysGroupByAsTableWhenFlagged() {
    RollupCalculator calc = getCalculator(
      null,
      Rollup.Op.SUM,
      Opportunity.Amount,
      Account.Description,
      new Rollup__mdt(CalcItem__c = String.valueOf(Opportunity.SObjectType), GroupByFields__c = 'StageName, Name', IsTableFormatted__c = true),
      RollupTestUtils.createId(Account.SObjectType),
      Account.Id
    );

    calc.performRollup(
      new List<SObject>{
        new Opportunity(StageName = 'Two', Name = 'Deux', Amount = 50),
        new Opportunity(StageName = 'Two', Name = 'Deux', Amount = 50),
        new Opportunity(StageName = 'One', Amount = 50),
        new Opportunity(StageName = 'One', Amount = 50)
      },
      new Map<Id, SObject>()
    );

    String tableHeader = '<tr><th>Stage</th><th>Name</th><th>Amount</th></tr>';
    String firstTableBodyRow = '<tr><td>One</td><td>(blank)</td><td>100.0</td></tr>';
    String secondTableBodyRow = '<tr><td>Two</td><td>Deux</td><td>100.0</td></tr>';
    System.assertEquals('<table>' + tableHeader + firstTableBodyRow + secondTableBodyRow + '</table>', calc.getReturnValue());
  }

  @IsTest
  static void averageFactorsInBatchState() {
    Rollup__mdt meta = new Rollup__mdt();
    String lookupKey = RollupTestUtils.createId(Account.SObjectType);
    RollupState outerState = new RollupState();
    RollupState.AverageInfo state = (RollupState.AverageInfo) outerState.getState(lookupKey, meta, RollupState.AverageInfo.class);
    state.denominator = 15;
    state.numerator = 75;
    RollupCalculator calc = getCalculator(
      state.numerator / state.denominator,
      Rollup.Op.AVERAGE,
      Opportunity.Amount,
      Account.Description,
      meta,
      lookupKey,
      Account.Id
    );
    calc.setState(outerState);

    calc.performRollup(
      new List<SObject>{
        new Opportunity(Amount = 15),
        new Opportunity(Amount = 15),
        new Opportunity(Amount = 15),
        new Opportunity(Amount = 15),
        new Opportunity(Amount = 15)
      },
      new Map<Id, SObject>()
    );

    Assert.areEqual(7.5, calc.getReturnValue());
  }

  @IsTest
  static void valuesCalculatorUpdatesOperationCorrectly() {
    RollupCalculator calc = getCalculator(
      0,
      Rollup.Op.SUM,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    RollupCalculator.ValueRollupCalculator outerCalc = new RollupCalculator.ValueRollupCalculator(calc, new List<Object>{ 2, 3 });
    outerCalc.setOperation(Rollup.Op.MAX);

    Assert.areEqual(3, outerCalc.getReturnValue());
  }

  private class RollupCalcEmptyMock extends RollupCalculator {
  }

  private static RollupCalculator getCalculator(
    Object priorVal,
    Rollup.Op operation,
    SObjectField calcItemField,
    SObjectField rollupField,
    Rollup__mdt meta,
    String lookupKey,
    SObjectField lookupField
  ) {
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(operation, calcItemField, rollupField, meta, lookupField);
    calc.setDefaultValues(lookupKey, priorVal);
    return calc;
  }

  private static Rollup__mdt configureOrderByMetadata(Rollup__mdt metadata, String orderByFirstLastFieldName) {
    List<RollupOrderBy__mdt> children = new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(FieldName__c = orderByFirstLastFieldName, Ranking__c = 0) };
    return Rollup.appendOrderByMetadata(metadata, children);
  }
}
