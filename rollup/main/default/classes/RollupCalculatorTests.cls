@isTest
private class RollupCalculatorTests {
  @isTest
  static void shouldReturnFirstValueBasedOnMetadataField() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate');
    RollupCalculator calc = RollupCalculator.getCalculator(
      0,
      Rollup.Op.FIRST,
      Opportunity.Amount,
      Account.AnnualRevenue,
      metadata,
      '0011g00003VDGbF002',
      Account.Id
    );

    // the important part is that the middle item is the one used, to prove that sorting occurred
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

  // TODO tests for nulls being placed last, different types being used (String, Number)
}
