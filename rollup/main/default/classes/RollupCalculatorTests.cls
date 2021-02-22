@isTest
private class RollupCalculatorTests {
  // TODO - refactor RollupTests so that the different *calculator type*-based tests live here instead

  /** FIRST / LAST operations */
  @isTest
  static void shouldReturnFirstValueBasedOnMetadataField() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate');
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

  @isTest
  static void shouldReturnLastValueBasedOnMetadataField() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate');
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

  @isTest
  static void shouldReturnFirstValueIfOtherOrderByValueIsNull() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate');
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

  @isTest
  static void shouldReturnLastValueIfOtherOrderByValueIsNull() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate');
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

  @isTest
  static void shouldNotSortAtAllIfOrderByValuesAreNull() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate');
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

    calc.performRollup(
      opps,
      new Map<Id, SObject>()
    );

    System.assertEquals(opps[0].Amount, (Decimal) calc.getReturnValue());
  }

  @isTest
  static void shouldReturnFirstString() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'Name');
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

  @isTest
  static void shouldReturnLastString() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'Name');
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

  @isTest
  static void shouldReturnFirstNumber() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'Amount');
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

  @isTest
  static void shouldReturnLastNumber() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'Amount');
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
}
