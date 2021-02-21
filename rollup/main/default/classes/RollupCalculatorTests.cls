@isTest
private class RollupCalculatorTests {
  @isTest
  static void shouldReturnFirstValueBasedOnMetadataField() {
    Rollup__mdt metadata = new Rollup__mdt(OrderByFirstLast__c = 'CloseDate');
    RollupCalculator calc = RollupCalculator.getCalculator(0, Rollup.Op.FIRST, Opportunity.Amount, Account.AnnualRevenue, metadata, '001000000001', Account.Id);

    calc.performRollup(
      new List<Opportunity>{ new Opportunity(Amount = 1, CloseDate = System.today().addDays(2)), new Opportunity(Amount = 2, CloseDate = System.today()) },
      new Map<Id, SObject>()
    );

    System.assertEquals(2 , (Decimal)calc.getReturnValue());
  }
}
