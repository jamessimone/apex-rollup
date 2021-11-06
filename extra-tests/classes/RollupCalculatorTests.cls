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
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

    calc.performRollup(new List<Opportunity>(), new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnFirstValueBasedOnMetadataField() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.LAST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
  static void shouldReturnMiddleValueWhenFirstAndLastAreNull() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
  static void shouldReturnFirstValueWhenMiddleAndLastAreNull() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'Name', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'Name', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.LAST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'Amount', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'Amount', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.LAST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'Name', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

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
  static void regressionShouldExcludeCurrentItemsOnFirstLastDelete() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'Name', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.DELETE_FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

    calc.performRollup(
      new List<Opportunity>{
        new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, Name = 'b'),
        new Opportunity(Id = '0066g00003VDGbF002', Amount = 16, Name = 'a'),
        new Opportunity(Id = '0066g00003VDGbF003', Amount = 1, Name = 'c')
      },
      new Map<Id, SObject>()
    );

    System.assertEquals(null, calc.getReturnValue(), 'Delete should exclude current values :(');
  }

  @IsTest
  static void regressionShouldIncludeCalcItemWhereClauseInQueryFieldsFirst() {
    Account acc = [SELECT Id FROM Account];
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'Name', CalcItem__c = 'ContactPointAddress', CalcItemWhereClause__c = 'PreferenceRank != 0');

    ContactPointAddress first = new ContactPointAddress(Name = 'a', ParentId = acc.Id, PreferenceRank = 1);
    insert first;

    ContactPointAddress cpa = new ContactPointAddress(
      Name = 'b',
      PreferenceRank = 1,
      ParentId = acc.Id,
      Id = RollupTestUtils.createId(ContactPointAddress.SObjectType)
    );

    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.FIRST,
      ContactPointAddress.NAME,
      Account.Description,
      metadata,
      acc.Id,
      ContactPointAddress.ParentId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator(metadata.CalcItemWhereClause__c, ContactPointAddress.SObjectType));

    calc.performRollup(new List<ContactPointAddress>{ cpa }, new Map<Id, SObject>());

    System.assertEquals(first.Name, calc.getReturnValue(), 'First should properly query');
  }

  // AVERAGE tests

  @IsTest
  static void shouldReturnDefaultWhenNoCalcItemsAverage() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate', CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.Average,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

    calc.performRollup(new List<Opportunity>(), new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void shouldNotTryToAverageNull() {
    Rollup__mdt metadata = new Rollup__mdt(CalcItem__c = 'Opportunity');
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.AVERAGE,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Opportunity.Id
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

    System.assertEquals(1, (Decimal) calc.getReturnValue(), 'Nulls should be treated as zeros for average!');
  }

  // COUNT tests

  @IsTest
  static void shouldReturnNewValOnCountChangeIfReparenting() {
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
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
  static void shouldReturnZeroOnFullRecalcIfNoMatchingItemsCount() {
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.COUNT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount != ' + opp.Amount, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(0, calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnZeroOnFullRecalcIfNoItemsPresentCount() {
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.COUNT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    calc.performRollup(new List<SObject>(), new Map<Id, SObject>());

    System.assertEquals(0, calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnZeroOnFullRecalcIfNoMatchingItemsCountDistinct() {
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.COUNT_DISTINCT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount != ' + opp.Amount, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(0, calc.getReturnValue());
  }

  @IsTest
  static void shouldNotDoubleCountDistinctForDeletions() {
    Account acc = [SELECT Id FROM Account];
    insert new Contact(LastName = 'Count Distinct', AccountId = acc.Id);

    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
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

    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      1,
      Rollup.Op.UPDATE_COUNT_DISTINCT,
      Opportunity.Id,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
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
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.UPDATE_COUNT,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
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
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.UPDATE_COUNT,
      Opportunity.Name,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
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
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      1,
      Rollup.Op.UPDATE_COUNT,
      Opportunity.Name,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
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

  // SUM tests

  @IsTest
  static void shouldReturnNullOnFullRecalcIfNoMatchingItemsSum() {
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.SUM,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Amount = 2, AccountId = '0016g00003VDGbF001');
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount != ' + opp.Amount, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void shouldReturnSumIfRollupValueUnchangedButEvalStatusHas() {
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      0,
      Rollup.Op.UPDATE_SUM,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
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

    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      5,
      Rollup.Op.UPDATE_SUM,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
      acc.Id,
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));
    Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>{ opp.Id => opp };

    calc.performRollup(new List<Opportunity>{ newerOpp }, oldOppMap);

    System.assertEquals(0, calc.getReturnValue());
  }

  // CONCAT tests

  @IsTest
  static void shouldReturnDefaultIfNoMatchingItemsPassedConcat() {
    String distinct = 'distinct';
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      distinct,
      Rollup.Op.CONCAT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );

    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = distinct, AccountId = '0016g00003VDGbF001');
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Name != ' + opp.Name, Opportunity.SObjectType));

    calc.performRollup(new List<Opportunity>{ opp }, new Map<Id, SObject>());

    System.assertEquals(null, calc.getReturnValue());
  }

  @IsTest
  static void shouldProperlyRemoveConcatOnUpdateIfOldItemMatchesAndNewOneDoesNot() {
    Opportunity opp = new Opportunity(AccountId = '0011g00003VDGbF002', Id = '0066g00003VDGbF001', Name = 'CDC', Amount = 0);

    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      'GISS, CDC',
      Rollup.Op.UPDATE_CONCAT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
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
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      distinct,
      Rollup.Op.CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(),
      '0011g00003VDGbF002',
      Opportunity.AccountId
    );
    Opportunity opp = new Opportunity(Id = '0066g00003VDGbF001', Name = distinct, AccountId = '0016g00003VDGbF001');
    Opportunity nonDistinctOpp = new Opportunity(Id = '0066g00003VDGbF001', Name = 'non' + distinct, AccountId = '0016g00003VDGbF001');
    calc.performRollup(new List<Opportunity>{ opp, nonDistinctOpp }, new Map<Id, SObject>());

    System.assertEquals(
      distinct +
      ', ' +
      nonDistinctOpp.Name,
      (String) calc.getReturnValue(),
      'Value containing original distinct value should also be concatenated'
    );
  }

  @IsTest
  static void shouldUseCustomConcatDelimiterWhenSupplied() {
    String distinct = 'distinct';
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
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
  static void shouldSplitCalcItemsOnConcatDelimiterWhenSupplied() {
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
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
  static void shouldProperlyRemoveConcatDistinctOnUpdateIfOldItemMatchesAndNewOneDoesNot() {
    String accountId = '0011g00003VDGbF002';
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      'CDC, GISS',
      Rollup.Op.UPDATE_CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(),
      accountId,
      Opportunity.AccountId
    );
    calc.setEvaluator(new RollupEvaluator.WhereFieldEvaluator('Amount > 0', Opportunity.SObjectType));
    Opportunity opp = new Opportunity(Amount = 0, Id = '0066g00003VDGbF001', Name = 'CDC', AccountId = accountId);
    Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>{ opp.Id => new Opportunity(Amount = 5, Name = 'CDC') };

    calc.performRollup(new List<Opportunity>{ opp }, oldOppMap);

    System.assertEquals('GISS', calc.getReturnValue());
  }

  @IsTest
  static void shouldNotRemoveValuesOnConcatDistinctDeleteIfItemDoesNotMatch() {
    Account acc = [SELECT Id FROM Account];

    insert new Opportunity(AccountId = acc.Id, StageName = 'hi', CloseDate = System.today(), Name = 'Delete');

    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      'CDC, Delete',
      Rollup.Op.DELETE_CONCAT_DISTINCT,
      Opportunity.Name,
      Account.Name,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
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
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
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
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
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
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
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

  // MIN / MAX

  @IsTest
  static void shouldDefaultToNullIfCurrentItemExcludedAndNoOtherMatchingItemsTime() {
    Time max = Time.newInstance(11, 11, 11, 11);
    Rollup__mdt metadata = new Rollup__mdt(CalcItem__c = 'ContactPointAddress', CalcItemWhereClause__c = 'BestTimeToContactEndTime != ' + String.valueOf(max));
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
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
  static void shouldDefaultToCurrentValueOnMinIfNoOtherMatchingItemsDate() {
    Rollup__mdt metadata = new Rollup__mdt();
    Date today = System.today();
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      today,
      Rollup.Op.UPDATE_MIN,
      Task.ActivityDate, // not a "MIN"-able field in SOQL; crucial for this test
      Opportunity.CloseDate,
      metadata,
      RollupTestUtils.createId(Opportunity.SObjectType),
      Task.WhatId
    );

    // the important things here: the current date is greater than both the passed in date (the "current" value on the lookup object)
    // AND that the "current" value matches what's on the old item
    Task t = new Task(ActivityDate = today.addDays(1), Id = RollupTestUtils.createId(Task.SObjectType));

    calc.performRollup(new List<Task>{ t }, new Map<Id, SObject>{ t.Id => new Task(ActivityDate = today) });

    System.assertEquals(t.ActivityDate, calc.getReturnValue(), 'Should be nulled out if no matching minimum');
  }

  @IsTest
  static void shouldDefaultToCurrentValueOnMinIfNoOtherMatchingItemsTime() {
    Rollup__mdt metadata = new Rollup__mdt();
    Time max = Time.newInstance(11, 11, 11, 11);
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
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
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
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
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      today,
      Rollup.Op.UPDATE_MAX,
      Task.ActivityDate, // not a "MAX"-able field in SOQL; crucial for this test
      Opportunity.CloseDate,
      metadata,
      RollupTestUtils.createId(Opportunity.SObjectType),
      Task.WhatId
    );

    // the important things here: the current date is less than both the passed in date (the "current" value on the lookup object)
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

    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      5,
      Rollup.Op.UPDATE_MIN,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
      acc.Id,
      Opportunity.AccountId
    );
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

    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      5,
      Rollup.Op.UPDATE_MAX,
      Opportunity.Amount,
      Account.AnnualRevenue,
      new Rollup__mdt(CalcItem__c = 'Opportunity'),
      acc.Id,
      Opportunity.AccountId
    );
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
    RollupCalculator calc = RollupCalculator.Factory.getCalculator(
      '',
      Rollup.Op.CONCAT_DISTINCT,
      Case.Description,
      Account.Description,
      meta,
      acc.Id,
      Account.Id
    );
    calc.setEvaluator(RollupEvaluator.getWhereEval(meta.CalcItemWhereClause__c, Case.SObjectType));
    calc.performRollup(new List<Case>{ cas }, new Map<Id, Case>());

    System.assertEquals(null, calc.getReturnValue());
  }

  // Factory tests

  @IsTest
  static void shouldThrowExceptionIfTypeNotSupported() {
    Exception ex;

    try {
      RollupCalculator calc = RollupCalculator.Factory.getCalculator(
        Blob.valueOf(''), // unsupported type
        Rollup.Op.CONCAT,
        Opportunity.Name,
        QuickText.Channel,
        new Rollup__mdt(),
        RollupTestUtils.createId(QuickText.SObjectType),
        QuickText.Name
      );
      calc.getReturnValue();
    } catch (Exception e) {
      ex = e;
    }

    System.assertNotEquals(null, ex, 'Exception should have been thrown');
  }

  @IsTest
  static void shouldInvokeNoOpMethodsWithoutFail() {
    RollupCalculator calc = new RollupCalcEmptyMock();
    calc.handleCountDistinct(null);
    calc.handleUpdateCountDistinct(null);
    calc.handleSumOrCount(null);
    calc.handleUpdateSumOrCount(null, null);
    calc.handleDeleteSumOrCount(null);
    calc.handleMin(null);
    calc.handleMax(null);
    calc.handleUpdateMinOrMax(null, null);
    calc.handleConcat(null);
    calc.handleUpdateConcat(null, null);
    calc.handleDeleteConcat(null);

    System.assert(true, 'Should make it here');
  }

  private class RollupCalcEmptyMock extends RollupCalculator {
    public RollupCalcEmptyMock() {
      super(0, Rollup.Op.LAST, null, null, null, new Rollup__mdt(), null, null);
    }
  }
}
