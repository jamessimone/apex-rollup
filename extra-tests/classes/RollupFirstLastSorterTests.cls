@IsTest
private class RollupFirstLastSorterTests {
  @IsTest
  static void shouldOrderByMultipleFields() {
    RollupFirstLastSorter sorter = new RollupFirstLastSorter(
      Rollup.Op.FIRST,
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount'),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate')
      }
    );

    Date severalDaysAgo = System.today().addDays(-2);
    Opportunity expectedFirstItem = new Opportunity(Amount = null, CloseDate = severalDaysAgo);
    Opportunity expectedSecondItem = new Opportunity(Amount = 1, CloseDate = severalDaysAgo);
    List<Opportunity> oppsToSort = new List<Opportunity>{
      new Opportunity(Amount = 1, CloseDate = System.today()),
      // this record should essentially be thrown out of sorting since it "loses" on the first ordering,
      // which is on Amount
      new Opportunity(Amount = 3, CloseDate = severalDaysAgo.addDays(-1)),
      expectedFirstItem,
      expectedSecondItem
    };
    sorter.sort(oppsToSort);

    System.assertEquals(expectedFirstItem, oppsToSort[0]);
    System.assertEquals(expectedSecondItem, oppsToSort[1]);
  }

  @IsTest
  static void shouldOrderNullsLast() {
    RollupFirstLastSorter sorter = new RollupFirstLastSorter(
      Rollup.Op.FIRST,
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount', NullSortOrder__c = RollupMetaPicklists.NullSortOrder.NullsLast),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate')
      }
    );

    Date severalDaysAgo = System.today().addDays(-2);
    Opportunity expectedFirstItem = new Opportunity(Amount = 1, CloseDate = System.today());
    Opportunity expectedSecondItem = new Opportunity(Amount = 3, CloseDate = severalDaysAgo.addDays(-1));
    List<Opportunity> oppsToSort = new List<Opportunity>{
      new Opportunity(Amount = 3, CloseDate = severalDaysAgo.addDays(-1)),
      expectedSecondItem,
      expectedFirstItem
    };
    sorter.sort(oppsToSort);

    System.assertEquals(expectedFirstItem, oppsToSort[0]);
    System.assertEquals(expectedSecondItem, oppsToSort[1]);
  }
}
